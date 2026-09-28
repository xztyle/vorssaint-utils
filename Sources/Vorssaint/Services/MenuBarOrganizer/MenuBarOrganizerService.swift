// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Backend adapted from ruvelro's Vorssaint PR #360, head 8d0888a.
import AppKit
import Combine

@MainActor
final class MenuBarOrganizerService: ObservableObject {
    static let shared = MenuBarOrganizerService()
    @Published var items: [ManagedMenuBarItem] = []
    @Published var capabilities = MenuBarOrganizerCapabilities.unavailable
    @Published var isRunning = false
    @Published var hiddenSectionShown = true
    @Published var alwaysHiddenSectionShown = true
    @Published var operationMessage: String?
    @Published var conflictingManagers: [MenuBarManagerDetection.RunningManager] = []
    @Published var library = MenuBarLibrary()
    @Published var isBusy = false
    @Published var recoveryNeeded = false
    @Published var shortcutRegistrationFailed = false
    @Published var automationPaused = false
    let provider = MenuBarWindowProvider()
    let mover = MenuBarItemMover()
    let store = MenuBarLayoutStore(defaults: .standard)
    var controlItem: MenuBarDividerItem?
    var hiddenDivider: MenuBarDividerItem?
    var alwaysHiddenDivider: MenuBarDividerItem?
    var secondaryPanel: MenuBarOrganizerPanelController?
    var refreshTimer: Timer?
    var refreshTask: Task<Void, Never>?
    var operationTask: Task<Void, Never>?
    var observers: [(NotificationCenter, NSObjectProtocol)] = []
    var hotkeys: [GlobalShortcutRole: QuickToolHotkey] = [:]
    var editingCount = 0
    var preEditingState: (hidden: Bool, always: Bool)?
    var undoLayout: MenuBarLayout?
    var desiredLayout = MenuBarLayout()
    var baseline: MenuBarLayout?
    var consumedRules: Set<UUID> = []
    var activeRule: MenuBarRevealRule?
    var ruleExpires: Date?
    var candidateRule: UUID?
    var candidateSince = Date.distantPast
    var reconciliationFailures = 0
    var needsReconciliation = true
    var inventoryWindows: [MenuBarItemIdentity: CGWindowID] = [:]
    var refreshGeneration = UUID()
    var libraryIsValid = true
    var stopping = false
    var quitRestorationRequested = false
    var pendingActivationRestore: MenuBarLayout?
    var pendingActivationVisibility: (Bool, Bool)?
    var canUndo: Bool { undoLayout != nil }
    var text: MenuBarOrganizerStrings { FeatureStrings.menuBarOrganizer(L10n.shared.language) }
    var extra: MenuBarProductStrings { .localized(L10n.shared.language) }

    private init() {}

    var entryAllowed: Bool {
        !stopping && isRunning && libraryIsValid && AppFeature.menuBarOrganizer.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.menuBarOrganizerEnabled)
            && AppFeature.menuBarOrganizer.isSupportedOnCurrentSystem && AXIsProcessTrusted()
            && MenuBarManagerDetection.runningManagers().isEmpty
    }

    func syncWithPreferences() {
        conflictingManagers = MenuBarManagerDetection.runningManagers()
        let enabled = AppFeature.menuBarOrganizer.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.menuBarOrganizerEnabled)
        guard enabled, AppFeature.menuBarOrganizer.isSupportedOnCurrentSystem,
              AXIsProcessTrusted(), conflictingManagers.isEmpty else {
            stop()
            return
        }
        guard !stopping else { return }
        if isRunning { reloadLibrary(); syncHotkeys(); applyDividerState(); return }
        guard operationTask == nil else { return }
        operationTask = Task { [weak self] in await self?.start() }
    }

    func start() async {
        defer { if !stopping { operationTask = nil } }
        do { try loadStoredState() }
        catch { libraryIsValid = false; operationMessage = extra.corruptStore; return }
        let snapshot = await provider.snapshot(hiddenDividerMidX: nil,
            alwaysHiddenDividerMidX: nil, excludedWindowIDs: [])
        guard !Task.isCancelled, snapshot.enumerationSucceeded, !snapshot.items.isEmpty else {
            operationMessage = text.automaticMoveUnavailable; return
        }
        let pendingRecovery: Bool
        do { pendingRecovery = try prepareBaseline(from: snapshot.items) }
        catch { operationMessage = extra.corruptStore; return }
        guard !Task.isCancelled, AppFeature.menuBarOrganizer.isAvailable,
              UserDefaults.standard.bool(forKey: DefaultsKey.menuBarOrganizerEnabled),
              AXIsProcessTrusted(), MenuBarManagerDetection.runningManagers().isEmpty else { return }
        createControls()
        isRunning = true
        recoveryNeeded = pendingRecovery
        automationPaused = pendingRecovery
        if pendingRecovery { operationMessage = extra.restoreFailed }
        installObservers()
        syncHotkeys()
        scheduleRefreshTimer()
        _ = await refreshNow()
        if !pendingRecovery && !desiredLayout.entries.isEmpty { await reconcile() }
    }

    private func loadStoredState() throws {
        library = try store.library()
        desiredLayout = try store.layout(for: DefaultsKey.menuBarOrganizerLayout) ?? MenuBarLayout()
        baseline = try store.layout(for: DefaultsKey.menuBarOrganizerBaseline)
        libraryIsValid = true
    }

    private func prepareBaseline(from items: [ManagedMenuBarItem]) throws -> Bool {
        if baseline == nil {
            let original = MenuBarLayout.capture(items, original: true)
            try store.save(original, for: DefaultsKey.menuBarOrganizerBaseline)
            baseline = original
        }
        return baseline.map { !MenuBarLayoutPolicy.isSatisfied($0, items: items) } ?? false
    }

    func createControls() {
        controlItem = MenuBarDividerItem(kind: .control)
        hiddenDivider = MenuBarDividerItem(kind: .hidden)
        alwaysHiddenDivider = MenuBarDividerItem(kind: .alwaysHidden)
        controlItem?.onLeftClick = { [weak self] in self?.toggleHiddenSection() }
        controlItem?.onRightClick = { [weak self] in self?.showContextMenu() }
        hiddenDivider?.onLeftClick = { [weak self] in self?.toggleHiddenSection() }
        alwaysHiddenDivider?.onLeftClick = { [weak self] in self?.toggleAlwaysHiddenSection() }
        secondaryPanel = MenuBarOrganizerPanelController(service: self)
        let setup = UserDefaults.standard.bool(forKey: DefaultsKey.menuBarOrganizerSetupComplete)
        hiddenSectionShown = !setup
        alwaysHiddenSectionShown = !setup
        applyDividerState()
    }

    func retryStart() {
        guard !recoveryNeeded else { operationMessage = extra.restoreFailed; return }
        automationPaused = false
        reconciliationFailures = 0
        needsReconciliation = true
        syncWithPreferences()
        refresh()
    }

    func refresh() {
        guard entryAllowed, !isBusy, refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            _ = await refreshNow()
            await evaluateAutomation()
            refreshTask = nil
        }
    }

    @discardableResult
    func refreshNow() async -> MenuBarItemSnapshot? {
        guard isRunning else { return nil }
        let generation = refreshGeneration
        let excluded = Set([controlItem?.windowID, hiddenDivider?.windowID,
                            alwaysHiddenDivider?.windowID].compactMap { $0 })
        let snapshot = await provider.snapshot(hiddenDividerMidX: hiddenDivider?.frame?.midX,
            alwaysHiddenDividerMidX: alwaysHiddenDivider?.frame?.midX, excludedWindowIDs: excluded)
        guard !Task.isCancelled, generation == refreshGeneration, isRunning else { return nil }
        capabilities = snapshot.capabilities
        if snapshot.enumerationSucceeded {
            items = snapshot.items
            let windows = Dictionary(uniqueKeysWithValues: items.filter { $0.identityState == .stable }.map { ($0.id, $0.windowID) })
            if windows != inventoryWindows { needsReconciliation = true; inventoryWindows = windows }
        }
        else { operationMessage = text.automaticMoveUnavailable }
        return snapshot
    }

    func beginEditing() {
        editingCount += 1
        guard editingCount == 1, entryAllowed else { return }
        preEditingState = (hiddenSectionShown, alwaysHiddenSectionShown)
        revealInMenuBar(.alwaysHidden)
    }

    func endEditing() {
        editingCount = max(0, editingCount - 1)
        guard editingCount == 0 else { return }
        if let previous = preEditingState {
            hiddenSectionShown = previous.hidden
            alwaysHiddenSectionShown = previous.always
        }
        preEditingState = nil
        applyDividerState()
    }

    func completeSetup() {
        guard entryAllowed, capabilities.automaticEditorAvailable else { return }
        UserDefaults.standard.set(true, forKey: DefaultsKey.menuBarOrganizerSetupComplete)
        saveCurrentLayout()
        editingCount = 0
        preEditingState = nil
        hideAll()
    }

    func applyDividerState() {
        let setup = UserDefaults.standard.bool(forKey: DefaultsKey.menuBarOrganizerSetupComplete)
        let markers = editingCount > 0 || !setup
            || UserDefaults.standard.bool(forKey: DefaultsKey.menuBarOrganizerShowDividers)
        let length = MenuBarOrganizerSupport.collapsedLength(screenWidths: NSScreen.screens.map(\.frame.width))
        hiddenDivider?.setCollapsed(!hiddenSectionShown && editingCount == 0,
                                   markerVisible: markers, collapsedLength: length)
        alwaysHiddenDivider?.setCollapsed(!alwaysHiddenSectionShown && editingCount == 0,
                                         markerVisible: markers, collapsedLength: length)
    }

    func toggleHiddenSection() {
        guard entryAllowed else { return }
        if hiddenSectionShown || secondaryPanel?.isVisible == true { hideAll() }
        else { show(.hidden) }
    }

    func toggleAlwaysHiddenSection() {
        guard entryAllowed else { return }
        if alwaysHiddenSectionShown { hideAll() } else { show(.alwaysHidden) }
    }

    func show(_ section: MenuBarOrganizerSection) {
        guard entryAllowed else { return }
        let mode = MenuBarOrganizerPresentationMode.sanitized(
            UserDefaults.standard.string(forKey: DefaultsKey.menuBarOrganizerPresentationMode))
        let screen = activeScreen
        let width = items.filter { $0.section != .visible }.reduce(CGFloat(0)) { $0 + $1.frame.width }
        let available = screen?.auxiliaryTopRightArea?.width ?? (screen?.visibleFrame.width ?? 1024) * 0.45
        if MenuBarOrganizerSupport.shouldUseSecondaryBar(mode: mode, hiddenWidth: width,
            availableWidth: available, hasNotch: screen?.safeAreaInsets.top ?? 0 > 0) {
            showSecondaryBar(includeAlwaysHidden: section == .alwaysHidden)
        } else { revealInMenuBar(section) }
    }

    var activeScreen: NSScreen? {
        NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
    }

    func revealInMenuBar(_ section: MenuBarOrganizerSection) {
        hiddenSectionShown = true
        if section == .alwaysHidden { alwaysHiddenSectionShown = true }
        applyDividerState()
    }

    func showSecondaryBar(includeAlwaysHidden: Bool = false) {
        guard entryAllowed else { return }
        secondaryPanel?.show(anchor: controlItem?.frame, search: false, includeAlwaysHidden: includeAlwaysHidden)
        refresh()
    }

    func showSearch() {
        guard entryAllowed else { return }
        secondaryPanel?.show(anchor: controlItem?.frame, search: true, includeAlwaysHidden: true)
        refresh()
    }

    func hideAll() {
        guard isRunning, !stopping else { return }
        secondaryPanel?.close()
        hiddenSectionShown = false
        alwaysHiddenSectionShown = false
        applyDividerState()
    }

    func clearOperationMessage() { operationMessage = nil }
}

extension MenuBarOrganizerCapabilities {
    static let unavailable = Self(canEnumerate: false, canMove: false,
                                  hasPrivateWindowList: false, unresolvedItemCount: 0)
}

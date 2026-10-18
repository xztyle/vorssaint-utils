// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import AppKit
import os

@MainActor
extension MenuBarOrganizerService {
    func move(itemID: MenuBarItemIdentity, before targetID: MenuBarItemIdentity?,
              to section: MenuBarOrganizerSection) {
        guard entryAllowed, !isBusy, operationTask == nil else { return }
        operationTask = Task { [weak self] in
            guard let self else { return }
            defer { if !stopping { operationTask = nil } }
            undoLayout = MenuBarLayout.capture(items)
            if await moveItem(itemID, before: targetID, to: section) { saveCurrentLayout() }
        }
    }

    func moveItem(_ identity: MenuBarItemIdentity, before target: MenuBarItemIdentity?,
                  to section: MenuBarOrganizerSection, restoring: Bool = false) async -> Bool {
        guard restoring || !recoveryNeeded else { operationMessage = extra.restoreFailed; return false }
        guard (restoring ? restoreAllowed : entryAllowed), target != identity else { return false }
        revealInMenuBar(.alwaysHidden)
        if usesNativeBackend { return await moveNativeItem(identity, before: target, to: section) }
        await provider.invalidateIdentityCache()
        guard await settleAndRefresh(), let current = items.first(where: { $0.id == identity }),
              current.isMovable, current.identityState == .stable,
              let destination = destination(for: section, before: target, excluding: identity)
        else { operationMessage = text.errorUnavailable; return false }
        guard restoring ? restoreAllowed : entryAllowed else { return false }
        let beforeMove = items
        return await performVerifiedMove(current, destination: destination, before: beforeMove, target: target, section: section)
    }

    private func performVerifiedMove(_ current: ManagedMenuBarItem, destination: MenuBarMoveDestination,
                                     before beforeMove: [ManagedMenuBarItem], target: MenuBarItemIdentity?,
                                     section: MenuBarOrganizerSection) async -> Bool {
        let logger = Logger(subsystem: "io.github.xztyle.Aster", category: "MenuBarMove")
        logger.notice("Menu move: source \(current.windowID), x \(current.frame.minX), destination \(destination.windowID), x \(destination.frame.minX)")
        do {
            try await mover.move(item: current, destination: destination)
            guard await verifyMove(current, before: beforeMove, target: target, section: section) else {
                logger.error("Menu move failed physical layout verification")
                return false
            }
            operationMessage = nil
            return true
        } catch {
            logger.error("Menu move failed: \(String(describing: error), privacy: .public)")
            if let moveError = error as? MenuBarItemMoveError,
               case .verificationFailed = moveError { markUnsafeMove() }
            operationMessage = moveErrorMessage(error)
            return false
        }
    }

    private func verifyMove(_ original: ManagedMenuBarItem, before: [ManagedMenuBarItem],
                            target: MenuBarItemIdentity?, section: MenuBarOrganizerSection) async -> Bool {
        guard await settleAndRefresh(), let moved = items.first(where: { $0.id == original.id })
        else { markUnsafeMove(); return false }
        let window = moved.windowID == original.windowID
        let membership = moved.section == section
        let others = MenuBarLayoutPolicy.preservesUnmovedItems(original.id, before: before, after: items)
        let adjacent = target.map { MenuBarLayoutPolicy.satisfies(MenuBarMovePlanStep(identity: original.id,
            before: $0, section: section), items: items) } ?? true
        guard window, membership, others, adjacent else {
            Logger(subsystem: "io.github.xztyle.Aster", category: "MenuBarMove")
                .error("Menu verification: window \(window), section \(membership), others \(others), adjacent \(adjacent), x \(moved.frame.minX), y \(moved.frame.minY)")
            markUnsafeMove(); return false
        }
        return true
    }

    private func markUnsafeMove() {
        recoveryNeeded = true
        automationPaused = true
        operationMessage = text.errorVerification
    }

    func settleAndRefresh() async -> Bool {
        do { try await Task.sleep(for: .milliseconds(180)) } catch { return false }
        return await refreshNow()?.enumerationSucceeded == true
    }

    func destination(for section: MenuBarOrganizerSection,
                     before target: MenuBarItemIdentity?, excluding source: MenuBarItemIdentity) -> MenuBarMoveDestination? {
        if let target {
            guard let item = items.first(where: { $0.id == target }), item.section == section else { return nil }
            return MenuBarMoveGeometry.destination(before: item, excluding: source, items: items)
        }
        let divider = section == .alwaysHidden ? alwaysHiddenDivider : hiddenDivider
        guard let windowID = divider?.windowID,
              let frame = MenuBarWindowServerBridge.shared.frame(for: windowID) else { return nil }
        return .init(windowID: windowID, frame: frame, after: section == .visible)
    }

    func applyLayout(_ layout: MenuBarLayout, restoring: Bool = false) async -> Bool {
        guard restoring || !recoveryNeeded else { operationMessage = extra.restoreFailed; return false }
        guard layout.isValid, !isBusy else { return false }
        isBusy = true
        let previous = (hiddenSectionShown, alwaysHiddenSectionShown)
        defer {
            isBusy = false
            hiddenSectionShown = previous.0
            alwaysHiddenSectionShown = previous.1
            applyDividerState()
        }
        revealInMenuBar(.alwaysHidden)
        guard await settleAndRefresh() else { return false }
        if MenuBarLayoutPolicy.isSatisfied(layout, items: items) { return true }
        return await applyLayoutSteps(layout, restoring: restoring)
    }

    private func applyLayoutSteps(_ layout: MenuBarLayout, restoring: Bool) async -> Bool {
        for step in MenuBarLayoutPolicy.plan(layout, items: items) {
            if MenuBarLayoutPolicy.satisfies(step, items: items) { continue }
            guard !Task.isCancelled else { return false }
            let beforeStep = items
            if await moveItem(step.identity, before: step.before, to: step.section, restoring: restoring) { continue }
            guard restoring, await restorationMayContinue(after: beforeStep) else { return false }
        }
        return MenuBarLayoutPolicy.isSatisfied(layout, items: items)
    }

    private func restorationMayContinue(after before: [ManagedMenuBarItem]) async -> Bool {
        let logger = Logger(subsystem: "io.github.xztyle.Aster", category: "MenuBarMove")
        guard !Task.isCancelled, restoreAllowed, await settleAndRefresh() else {
            logger.error("Recovery stopped: cancellation, permission or inventory unavailable")
            return false
        }
        if let difference = MenuBarLayoutPolicy.topologyDifference(before: before, after: items) {
            logger.error("Recovery stopped: \(difference, privacy: .public)"); return false
        }
        logger.notice("Recovery move left the layout unchanged; checking remaining baseline moves")
        return true
    }

    func undoLastMove() {
        guard entryAllowed, let undoLayout, operationTask == nil else { return }
        operationTask = Task { [weak self] in
            guard let self else { return }
            defer { if !stopping { operationTask = nil } }
            if await applyLayout(undoLayout) {
                saveCurrentLayout()
                if MenuBarLayoutPolicy.allItemsAvailable(undoLayout, items: items) { self.undoLayout = nil }
                else { operationMessage = text.errorUnavailable }
            }
        }
    }

    func saveCurrentLayout() {
        guard libraryIsValid else { return }
        let captured = MenuBarLayout.capture(items)
        needsReconciliation = false
        desiredLayout = captured.preservingAbsent(from: desiredLayout, present: Set(items.filter { $0.identityState == .stable }.map(\.id)))
        do { try store.save(desiredLayout, for: layoutPreferenceKey) }
        catch { operationMessage = extra.corruptStore }
    }

    func activate(itemID: MenuBarItemIdentity) {
        guard entryAllowed, operationTask == nil, !isBusy else { return }
        secondaryPanel?.close()
        operationTask = Task { [weak self] in
            guard let self else { return }
            defer { if !stopping { operationTask = nil } }
            await activateItem(itemID)
        }
    }

    func activateItem(_ identity: MenuBarItemIdentity) async {
        guard await settleAndRefresh(), let original = items.first(where: { $0.id == identity }),
              original.identityState == .stable else { operationMessage = text.errorUnresolved; return }
        let restoreLayout = MenuBarLayout.capture(items)
        let previous = (hiddenSectionShown, alwaysHiddenSectionShown)
        pendingActivationRestore = restoreLayout
        pendingActivationVisibility = previous
        var keepExpanded = false
        defer { if !keepExpanded { restoreActivationVisibility(previous) } }
        revealInMenuBar(.alwaysHidden)
        guard await settleAndRefresh() else { return }
        if !itemIsReachable(identity), original.isMovable {
            guard await moveItem(identity, before: nil, to: .visible) else { return }
        }
        guard entryAllowed, let current = items.first(where: { $0.id == identity }), itemIsReachable(identity) else {
            operationMessage = extra.cannotReach; return
        }
        do { try await clickItem(current) }
        catch { operationMessage = moveErrorMessage(error) }
        guard await waitUntilMenuCloses() else { keepExpanded = true; return }
        if entryAllowed, await applyLayout(restoreLayout) { pendingActivationRestore = nil }
    }

    func restoreActivationVisibility(_ state: (Bool, Bool)) {
        hiddenSectionShown = state.0
        alwaysHiddenSectionShown = state.1
        applyDividerState()
    }

    func itemIsReachable(_ identity: MenuBarItemIdentity) -> Bool {
        guard let item = items.first(where: { $0.id == identity }) else { return false }
        return NSScreen.screens.contains { screen in
            let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
            let frame = CGRect(x: item.frame.minX, y: primaryHeight - item.frame.maxY,
                               width: item.frame.width, height: item.frame.height)
            let right = screen.auxiliaryTopRightArea
            return right.map { $0.contains(frame) } ?? screen.frame.contains(frame)
        }
    }

    func waitUntilMenuCloses() async -> Bool {
        for _ in 0..<600 {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return false }
            guard entryAllowed else { return false }
            if !MenuBarItemMover.hasAnyOpenMenu { return true }
        }
        return false
    }

    var restoreAllowed: Bool {
        isRunning && AppFeature.menuBarOrganizer.isSupportedOnCurrentSystem
            && AXIsProcessTrusted() && MenuBarManagerDetection.runningManagers().isEmpty
    }

    func stop() {
        guard !stopping else { return }
        let pending = operationTask
        pending?.cancel()
        operationTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        suspendObservers()
        guard isRunning else { return }
        stopping = true
        operationTask = Task { [weak self] in
            guard let self else { return }
            await pending?.value
            await restoreOriginalLayout()
            finishTermination()
            operationTask = nil
            stopping = false
        }
    }

    func restoreOriginalLayout() async {
        hiddenSectionShown = true
        alwaysHiddenSectionShown = true
        editingCount = 0
        applyDividerState()
        guard let baseline else { return }
        let restored = restoreAllowed ? await applyLayout(baseline, restoring: true) : false
        let missing = baseline.entries.contains { entry in !items.contains { $0.id == entry.identity } }
        recoveryNeeded = !restored || missing
        if restored && !missing {
            store.defaults.removeObject(forKey: baselinePreferenceKey)
            self.baseline = nil
        } else { operationMessage = extra.restoreFailed }
    }

    func restoreBeforeQuit(completion: @escaping () -> Void) {
        guard !quitRestorationRequested else { return }
        quitRestorationRequested = true
        Task { @MainActor in
            await prepareForTermination()
            quitRestorationRequested = false
            completion()
        }
    }

    func prepareForTermination() async {
        stopping = true
        operationTask?.cancel()
        if let task = operationTask { await task.value }
        guard isRunning else { return }
        stopping = true
        suspendObservers()
        await restoreOriginalLayout()
        finishTermination()
    }

    func prepareForSystemRemoval() async -> Bool {
        if isRunning { await prepareForTermination(); stopping = false }
        let pending = store.defaults.data(forKey: baselinePreferenceKey)
        return !recoveryNeeded && (pending == nil || pending?.isEmpty == true)
    }

    func finishTermination() {
        suspendObservers()
        if usesNativeBackend { nativeBackend.reset() }
        hiddenDivider?.expandForRemoval()
        alwaysHiddenDivider?.expandForRemoval()
        [controlItem, hiddenDivider, alwaysHiddenDivider].forEach { $0?.removePreservingPosition() }
        controlItem = nil
        hiddenDivider = nil
        alwaysHiddenDivider = nil
        isRunning = false
        items = []
        pendingActivationRestore = nil
        pendingActivationVisibility = nil
        refreshGeneration = UUID()
    }

    func moveErrorMessage(_ error: Error) -> String {
        guard let error = error as? MenuBarItemMoveError else { return error.localizedDescription }
        switch error {
        case .permissionMissing: return text.errorPermission
        case .itemUnavailable: return text.errorUnavailable
        case .itemNotMovable: return text.errorNotMovable
        case .provisionalIdentity: return text.errorUnresolved
        case .menuOpen: return text.errorMenuOpen
        case .eventCreationFailed: return text.errorEvent
        case .verificationFailed: return text.errorVerification
        case .busy: return text.errorBusy
        }
    }
}

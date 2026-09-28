// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import AppKit
import IOKit.ps

@MainActor
extension MenuBarOrganizerService {
    func scheduleRefreshTimer() {
        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func observe(_ center: NotificationCenter, _ name: Notification.Name,
                 action: @escaping @MainActor () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            Task { @MainActor in action() }
        }
        observers.append((center, token))
    }

    func installObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        for event in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                      NSWorkspace.didWakeNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            observe(workspace, event) { [weak self] in self?.environmentChanged() }
        }
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { [weak self] in self?.refresh() }
        observe(.default, NSApplication.didChangeScreenParametersNotification) { [weak self] in
            self?.environmentChanged()
        }
        observe(.default, UserDefaults.didChangeNotification) { [weak self] in self?.reloadLibrary(); self?.syncHotkeys() }
        observe(workspace, NSWorkspace.willSleepNotification) { [weak self] in
            self?.operationTask?.cancel()
            self?.secondaryPanel?.close()
        }
    }

    func environmentChanged() {
        conflictingManagers = MenuBarManagerDetection.runningManagers()
        guard conflictingManagers.isEmpty, AXIsProcessTrusted() else { stop(); return }
        secondaryPanel?.close()
        refreshGeneration = UUID()
        needsReconciliation = true
        Task { [weak self] in
            await self?.provider.invalidateIdentityCache()
            self?.applyDividerState()
            self?.refresh()
        }
    }

    func suspendObservers() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
        hotkeys.values.forEach { $0.unregister() }
        secondaryPanel?.close()
    }

    func syncHotkeys() {
        guard entryAllowed else { hotkeys.values.forEach { $0.unregister() }; return }
        shortcutRegistrationFailed = false
        for (offset, role) in GlobalShortcutRole.menuBarRoles.enumerated() {
            let key = hotkeys[role] ?? QuickToolHotkey(id: UInt32(160 + offset))
            key.onPress = { [weak self] in self?.invokeShortcut(role) }
            hotkeys[role] = key
            let shortcut = role.savedShortcut
            let conflict = GlobalShortcutRole.conflict(for: shortcut, excluding: role) != nil
                || shortcut.conflictsWithSystemShortcut(for: role)
            let succeeded = key.sync(enabled: !conflict && shortcut.isValid,
                                     shortcut: shortcut, storageKey: role.storageKey)
            if conflict || !succeeded { shortcutRegistrationFailed = true }
        }
    }

    func invokeShortcut(_ role: GlobalShortcutRole) {
        guard entryAllowed else { return }
        switch role {
        case .menuBarReveal: toggleHiddenSection()
        case .menuBarAlways: toggleAlwaysHiddenSection()
        case .menuBarPanel: showSecondaryBar()
        case .menuBarSearch: showSearch()
        case .menuBarProfile:
            guard !library.profiles.isEmpty else { return }
            let current = library.profiles.firstIndex { $0.id == library.activeProfileID } ?? -1
            applyProfile(library.profiles[(current + 1) % library.profiles.count].id)
        default: break
        }
    }

    func ruleFacts() -> MenuBarRuleFacts {
        let components = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let power = menuBarPowerFacts()
        return MenuBarRuleFacts(frontmostBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            onBattery: power.onBattery, batteryPercent: power.percent,
            minuteOfDay: (components.hour ?? 0) * 60 + (components.minute ?? 0),
            displayCount: NSScreen.screens.count, items: Set(items.filter { $0.identityState == .stable }.map(\.id)))
    }

    func menuBarPowerFacts() -> (onBattery: Bool?, percent: Int?) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return (nil, nil) }
        for source in sources {
            guard let values = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  values[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let current = values[kIOPSCurrentCapacityKey] as? Int
            let maximum = values[kIOPSMaxCapacityKey] as? Int
            let percent = current.flatMap { current in maximum.flatMap { $0 > 0 ? current * 100 / $0 : nil } }
            return ((values[kIOPSPowerSourceStateKey] as? String).map { $0 == kIOPSBatteryPowerValue }, percent)
        }
        return (nil, nil)
    }

    func evaluateAutomation() async {
        guard entryAllowed, !isBusy, operationTask == nil, editingCount == 0,
              !automationPaused, !recoveryNeeded, !MenuBarItemMover.hasAnyOpenMenu else { return }
        if await finishPendingActivation() { return }
        let facts = ruleFacts()
        consumedRules = consumedRules.filter { id in
            library.rules.first(where: { $0.id == id }).map { MenuBarRulePolicy.matches($0, facts: facts) } ?? false
        }
        let eligible = library.rules.filter { ruleIsActionable($0) }
        let winner = MenuBarRulePolicy.winner(eligible, facts: facts, consumed: consumedRules)
        if candidateRule != winner?.id { candidateRule = winner?.id; candidateSince = Date() }
        if let activeRule {
            if MenuBarRulePolicy.shouldEnd(activeRule, expires: ruleExpires, now: Date(),
                current: library.rules.first { $0.id == activeRule.id }, facts: facts) {
                await endRule()
            } else if let winner, winner.priority > activeRule.priority,
                      Date().timeIntervalSince(candidateSince) >= 1 {
                await endRule(); await runRule(winner)
            }
            return
        }
        if let winner, Date().timeIntervalSince(candidateSince) >= 1 { await runRule(winner) }
        else { await reconcile() }
    }

    func finishPendingActivation() async -> Bool {
        guard let pendingActivationRestore else { return false }
        if await applyLayout(pendingActivationRestore) {
            self.pendingActivationRestore = nil
            if let state = pendingActivationVisibility {
                hiddenSectionShown = state.0
                alwaysHiddenSectionShown = state.1
                applyDividerState()
            }
        }
        return true
    }

    func ruleIsActionable(_ rule: MenuBarRevealRule) -> Bool {
        switch rule.action {
        case .revealHidden: return true
        case .revealItem: return rule.item.map { id in items.contains { $0.id == id && $0.isMovable } } ?? false
        case .applyProfile:
            guard let profile = library.profiles.first(where: { $0.id == rule.profileID }) else { return false }
            return profile.layout.entries.contains { entry in items.contains { $0.id == entry.identity && $0.isMovable } }
        }
    }

    func runRule(_ rule: MenuBarRevealRule) async {
        guard entryAllowed else { return }
        let layout = ruleLayout(rule)
        if rule.action != .revealHidden, layout == nil { return }
        if let layout, !(await applyLayout(layout)) { recordReconciliationFailure(); return }
        consumedRules.insert(rule.id)
        activeRule = rule
        ruleExpires = Date().addingTimeInterval(rule.duration)
        if rule.action == .revealHidden { show(.hidden) }
        else { hideAll() }
    }

    func ruleLayout(_ rule: MenuBarRevealRule) -> MenuBarLayout? {
        switch rule.action {
        case .revealHidden: return nil
        case .applyProfile: return library.profiles.first { $0.id == rule.profileID }?.layout
        case .revealItem:
            guard let identity = rule.item, items.contains(where: { $0.id == identity && $0.isMovable }) else { return nil }
            return desiredLayout.withRevealed(identity)
        }
    }

    func endRule() async {
        activeRule = nil
        ruleExpires = nil
        if !desiredLayout.entries.isEmpty, !(await applyLayout(desiredLayout)) { recordReconciliationFailure() }
        hideAll()
    }

    func reconcile() async {
        guard entryAllowed, needsReconciliation, !desiredLayout.entries.isEmpty,
              !automationPaused, !recoveryNeeded, editingCount == 0,
              !MenuBarItemMover.hasAnyOpenMenu else { return }
        guard adoptNewItems() else { return }
        if MenuBarLayoutPolicy.isSatisfied(desiredLayout, items: items) {
            needsReconciliation = false
            return
        }
        if await applyLayout(desiredLayout) { reconciliationFailures = 0; needsReconciliation = false }
        else { recordReconciliationFailure() }
    }

    func adoptNewItems() -> Bool {
        let current = MenuBarLayout.capture(items, original: true)
        let updated = desiredLayout.includingNewItems(from: current)
        guard updated != desiredLayout else { return true }
        do {
            if let baseline {
                let original = baseline.includingNewItems(from: current)
                try store.save(original, for: DefaultsKey.menuBarOrganizerBaseline)
                self.baseline = original
            }
            try store.save(updated, for: DefaultsKey.menuBarOrganizerLayout)
            desiredLayout = updated
            return true
        } catch { operationMessage = extra.corruptStore; return false }
    }

    func recordReconciliationFailure() {
        reconciliationFailures += 1
        if reconciliationFailures >= 3 { automationPaused = true; operationMessage = extra.automationPaused }
    }

    func reloadLibrary() {
        do {
            let updated = try store.library()
            if updated != library { library = updated; consumedRules.removeAll() }
            libraryIsValid = true
        } catch { libraryIsValid = false; operationMessage = extra.corruptStore }
    }

    func saveLibrary(_ updated: MenuBarLibrary) {
        guard libraryIsValid else { return }
        do { try store.save(updated); library = updated }
        catch { operationMessage = extra.corruptStore }
    }

    func saveProfile(name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard entryAllowed, (1...120).contains(name.count), !items.isEmpty else { return }
        var updated = library
        updated.profiles.append(MenuBarProfile(name: name, layout: MenuBarLayout.capture(items)))
        saveLibrary(updated)
    }

    func renameProfile(_ id: UUID, name: String) {
        var updated = library
        guard let index = updated.profiles.firstIndex(where: { $0.id == id }) else { return }
        updated.profiles[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        saveLibrary(updated)
    }

    func deleteProfile(_ id: UUID) {
        var updated = library
        updated.profiles.removeAll { $0.id == id }
        if updated.activeProfileID == id { updated.activeProfileID = nil }
        saveLibrary(updated)
    }

    func applyProfile(_ id: UUID) {
        guard entryAllowed, operationTask == nil, let profile = library.profiles.first(where: { $0.id == id }) else { return }
        operationTask = Task { [weak self] in
            guard let self else { return }
            defer { if !stopping { operationTask = nil } }
            activeRule = nil
            if await applyLayout(profile.layout) {
                desiredLayout = profile.layout
                try? store.save(desiredLayout, for: DefaultsKey.menuBarOrganizerLayout)
                var updated = library
                updated.activeProfileID = id
                saveLibrary(updated)
            }
        }
    }

    func saveRule(_ rule: MenuBarRevealRule) {
        var updated = library
        if let index = updated.rules.firstIndex(where: { $0.id == rule.id }) { updated.rules[index] = rule }
        else { updated.rules.append(rule) }
        consumedRules.remove(rule.id)
        saveLibrary(updated)
    }

    func deleteRule(_ id: UUID) {
        var updated = library
        updated.rules.removeAll { $0.id == id }
        saveLibrary(updated)
    }
}

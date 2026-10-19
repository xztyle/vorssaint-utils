// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import AppKit

@MainActor
final class MenuBarNativeBackend {
    let layout = MenuBarNativeLayoutCoordinator()
    let visibility = MenuBarNativeVisibility()
    let mover = MenuBarNativeDragMover()
    var assignments: [MenuBarItemIdentity: MenuBarOrganizerSection] = [:]
    private var catalog: [MenuBarItemIdentity: ManagedMenuBarItem] = [:]
    private(set) var controlFrame: CGRect?

    func prepareForStartup() {
        visibility.reset()
        assignments.removeAll()
    }

    func loadSavedMembership(_ saved: MenuBarLayout, recovering: Bool) {
        guard !recovering else { return }
        assignments = Dictionary(uniqueKeysWithValues: saved.entries.map { ($0.identity, $0.section) })
    }

    func snapshot() async -> MenuBarItemSnapshot {
        let raw = await MenuBarNativeAXProvider.snapshot(includingOwn: true)
        guard raw.enumerationSucceeded else { return raw }
        let own = raw.items.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        controlFrame = own.first { $0.id.title == MenuBarDividerItem.Kind.control.autosaveName }.map { item in
            CGRect(x: item.frame.minX, y: (NSScreen.screens.first?.frame.maxY ?? 0) - item.frame.maxY,
                   width: item.frame.width, height: item.frame.height)
        }
        // Aster's own stats are listed like any app icon; its ✱ and ‹ are not.
        let fresh = raw.items.filter {
            $0.bundleIdentifier != Bundle.main.bundleIdentifier || MenuBarOwnStatVisibility.isOwnStat($0)
        }
        for item in fresh { catalog[item.id] = item }
        restoreSwitchedOffStats()
        let ids = Set(fresh.map(\.id))
        catalog = catalog.filter { ids.contains($0.key) || retainedHidden($0.value) }
        let items = catalog.values.map(decorate).sorted { $0.frame.minX < $1.frame.minX }
        return .init(items: items, capabilities: .init(canEnumerate: true, canMove: true,
            hasPrivateWindowList: false, unresolvedItemCount: items.filter { !$0.isMovable && !$0.isProtected }.count),
            enumerationSucceeded: true)
    }

    /// Always Hidden stats are switched off in Aster's settings, so the bar no
    /// longer draws them; they stay listed so they can be dragged back out.
    /// A stat the user switched on again in Aster's settings goes back to Visible.
    private func restoreSwitchedOffStats() {
        let ownStats = MenuBarOwnStatVisibility.shared
        for title in ownStats.switchedOff.keys {
            let identity = MenuBarItemIdentity(bundleIdentifier: Bundle.main.bundleIdentifier ?? "", title: title, occurrence: 0)
            if ownStats.forgetIfSwitchedBackOn(title) { assignments[identity] = .visible; continue }
            guard catalog[identity] == nil else { continue }
            if assignments[identity] == nil { assignments[identity] = .alwaysHidden }
            catalog[identity] = Self.switchedOffItem(identity)
        }
    }

    private static func switchedOffItem(_ identity: MenuBarItemIdentity) -> ManagedMenuBarItem {
        let pid = ProcessInfo.processInfo.processIdentifier
        return .init(id: identity, windowID: 0, ownerPID: pid, ownerBundleIdentifier: identity.bundleIdentifier,
            sourcePID: pid, ownerName: AppInfo.name, sourceName: AppInfo.name, bundleIdentifier: identity.bundleIdentifier,
            title: identity.title, frame: .zero, section: .alwaysHidden, identityState: .stable,
            isMovable: true, isProtected: false, image: nil)
    }

    private func retainedHidden(_ item: ManagedMenuBarItem) -> Bool {
        if MenuBarOwnStatVisibility.isOwnStat(item) {
            let ownStats = MenuBarOwnStatVisibility.shared
            return ownStats.hidden.contains(item.id.title) || ownStats.switchedOff[item.id.title] != nil
        }
        guard visibility.concealed.contains(item.bundleIdentifier), let pid = item.sourcePID,
              let publisher = NSRunningApplication(processIdentifier: pid) else { return false }
        return !publisher.isTerminated && publisher.bundleIdentifier == item.bundleIdentifier
    }

    private func decorate(_ item: ManagedMenuBarItem) -> ManagedMenuBarItem {
        .init(id: item.id, windowID: item.windowID, ownerPID: item.ownerPID,
            ownerBundleIdentifier: item.ownerBundleIdentifier, sourcePID: item.sourcePID,
            ownerName: item.ownerName, sourceName: item.sourceName, bundleIdentifier: item.bundleIdentifier,
            title: item.title, frame: item.frame, section: item.isProtected ? .visible : assignments[item.id] ?? .visible,
            identityState: item.identityState, isMovable: item.identityState == .stable && !item.isProtected,
            isProtected: item.isProtected, image: item.image)
    }

    func move(_ identity: MenuBarItemIdentity, before target: MenuBarItemIdentity?,
              to section: MenuBarOrganizerSection) async throws {
        guard let item = catalog[identity], item.identityState == .stable, !item.isProtected,
              section == .visible || !item.bundleIdentifier.hasPrefix("com.apple.") else { throw MenuBarItemMoveError.itemNotMovable }
        visibility.reset()
        await MenuBarOwnStatVisibility.shared.setHidden([]) // a hidden stat must be drawn to drag it
        // An Always Hidden stat is switched off, so it has no place in the bar.
        let switchedOff = await MenuBarOwnStatVisibility.shared.switchedOff
        let undrawn = MenuBarOwnStatVisibility.isOwnStat(identity) && section == .alwaysHidden
        if switchedOff[identity.title] != nil, section != .alwaysHidden { await switchOnAndWait(identity) }
        // Native hiding is independent of physical position. A section-only
        // choice must not reorder neighbors or require a compositor refresh.
        if let target, !undrawn, switchedOff[target.title] == nil { try await mover.move(identity, before: target) }
        assignments[identity] = section
    }

    func applyVisibility(hiddenShown: Bool, alwaysShown: Bool,
                         items: [ManagedMenuBarItem], failure: @escaping () -> Void) {
        let hidden = items.filter {
            $0.section == .hidden && !hiddenShown || $0.section == .alwaysHidden && !alwaysShown
        }
        // Aster always stays allowed in the system pass; it hides its own stats itself.
        applyOwnStatVisibility(items.filter(MenuBarOwnStatVisibility.isOwnStat),
                               hidden: Set(hidden.map(\.id)))
        let others = items.filter { !MenuBarOwnStatVisibility.isOwnStat($0) }
        visibility.apply(hidden: Set(hidden.filter { !MenuBarOwnStatVisibility.isOwnStat($0) }.map(\.id)),
                         items: others, failure: failure)
    }

    /// Hidden stats leave the bar until ‹ shows them; Always Hidden stats are
    /// switched off in Aster's settings, whatever the bar shows.
    private func applyOwnStatVisibility(_ stats: [ManagedMenuBarItem], hidden: Set<MenuBarItemIdentity>) {
        let ownStats = MenuBarOwnStatVisibility.shared
        for stat in stats {
            if stat.section == .alwaysHidden { ownStats.switchOff(stat.id.title) } else { ownStats.switchOn(stat.id.title) }
        }
        ownStats.setHidden(Set(stats.filter { $0.section == .hidden && hidden.contains($0.id) }.map(\.id.title)))
    }

    /// Switches the stat back on in Aster's settings and waits until the bar
    /// draws it, so it can be dragged into place.
    private func switchOnAndWait(_ identity: MenuBarItemIdentity) async {
        MenuBarOwnStatVisibility.shared.switchOn(identity.title)
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(200))
            let drawn = await MenuBarNativeAXProvider.snapshot(includingOwn: true)
            if drawn.items.contains(where: { $0.id == identity && $0.frame.width > 0 }) { return }
        }
    }

    func reset() {
        visibility.reset(); MenuBarOwnStatVisibility.shared.setHidden([])
        catalog = [:]; controlFrame = nil
    }
}

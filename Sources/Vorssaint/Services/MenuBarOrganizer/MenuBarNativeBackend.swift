// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import AppKit

@MainActor
final class MenuBarNativeBackend {
    let layout = MenuBarNativeLayoutCoordinator()
    let visibility = MenuBarNativeVisibility()
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
        let fresh = raw.items.filter { $0.bundleIdentifier != Bundle.main.bundleIdentifier }
        for item in fresh { catalog[item.id] = item }
        let ids = Set(fresh.map(\.id))
        catalog = catalog.filter { ids.contains($0.key) || retainedHidden($0.value) }
        let document = try? MenuBarNativeLayoutAccess.shared.read()
        let keyCounts = Dictionary(grouping: (Array(catalog.values) + own).compactMap { item in document.flatMap { layout.key(item, in: $0) } }, by: { $0 }).mapValues(\.count)
        let items = catalog.values.map { decorate($0, document: document, keyCounts: keyCounts) }.sorted { $0.frame.minX < $1.frame.minX }
        return .init(items: items, capabilities: .init(canEnumerate: true, canMove: document != nil,
            hasPrivateWindowList: false, unresolvedItemCount: items.filter { !$0.isMovable && !$0.isProtected }.count),
            enumerationSucceeded: true)
    }

    private func retainedHidden(_ item: ManagedMenuBarItem) -> Bool {
        guard visibility.concealed.contains(item.bundleIdentifier), let pid = item.sourcePID,
              let publisher = NSRunningApplication(processIdentifier: pid) else { return false }
        return !publisher.isTerminated && publisher.bundleIdentifier == item.bundleIdentifier
    }

    private func decorate(_ item: ManagedMenuBarItem, document: MenuBarNativeLayoutDocument?,
                          keyCounts: [String: Int]) -> ManagedMenuBarItem {
        let key = document.flatMap { layout.key(item, in: $0) }
        return .init(id: item.id, windowID: item.windowID, ownerPID: item.ownerPID,
            ownerBundleIdentifier: item.ownerBundleIdentifier, sourcePID: item.sourcePID,
            ownerName: item.ownerName, sourceName: item.sourceName, bundleIdentifier: item.bundleIdentifier,
            title: item.title, frame: item.frame, section: item.isProtected ? .visible : assignments[item.id] ?? .visible,
            identityState: item.identityState, isMovable: key.map { keyCounts[$0] == 1 } == true && !item.isProtected,
            isProtected: item.isProtected, image: item.image)
    }

    func move(_ identity: MenuBarItemIdentity, before target: MenuBarItemIdentity?,
              to section: MenuBarOrganizerSection) async throws {
        guard let item = catalog[identity], item.identityState == .stable, !item.isProtected,
              section == .visible || !item.bundleIdentifier.hasPrefix("com.apple.") else { throw MenuBarItemMoveError.itemNotMovable }
        visibility.reset()
        // Native hiding is independent of physical position. A section-only
        // choice must not reorder neighbors or require a compositor refresh.
        if target != nil { try await layout.move(identity, before: target) }
        assignments[identity] = section
    }

    func applyVisibility(hiddenShown: Bool, alwaysShown: Bool, editing: Bool,
                         items: [ManagedMenuBarItem], failure: @escaping () -> Void) {
        guard !editing else { visibility.reset(); return }
        let hidden = Set(items.filter {
            $0.section == .hidden && !hiddenShown || $0.section == .alwaysHidden && !alwaysShown
        }.map(\.id))
        visibility.apply(hidden: hidden, items: items, failure: failure)
    }

    func reset() { visibility.reset(); catalog = [:]; controlFrame = nil }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// WindowServer/AX backend adapted from Vorssaint PR #360 (ruvelro).
import AppKit

final class MenuBarWindowProvider {
    private let bridge = MenuBarWindowServerBridge.shared
    private let resolver = MenuBarItemSourceResolver()
    private let queue = DispatchQueue(label: "io.github.xztyle.Aster.menu-bar", qos: .utility)

    func snapshot(hiddenDividerMidX: CGFloat?, alwaysHiddenDividerMidX: CGFloat?,
                  excludedWindowIDs: Set<CGWindowID>) async -> MenuBarItemSnapshot {
        guard let records = await enumerate() else { return unavailable }
        let filtered = records.filter { !excludedWindowIDs.contains($0.windowID) }
        let sources = await resolver.resolve(records: filtered)
        let identities = MenuBarOrganizerSupport.identities(for: filtered, sources: sources)
        let items = await MainActor.run {
            filtered.compactMap { record -> ManagedMenuBarItem? in
                guard let resolved = identities[record.windowID] else { return nil }
                let section = MenuBarOrganizerSupport.section(itemMidX: record.frame.midX,
                    hiddenDividerMidX: hiddenDividerMidX, alwaysHiddenDividerMidX: alwaysHiddenDividerMidX)
                return Self.item(record, resolved: resolved, section: section)
            }.sorted { $0.frame.minX < $1.frame.minX }
        }
        return MenuBarItemSnapshot(items: items, capabilities: MenuBarOrganizerCapabilities(
            canEnumerate: true, canMove: AXIsProcessTrusted(), hasPrivateWindowList: true,
            unresolvedItemCount: items.filter { $0.identityState == .provisional }.count), enumerationSucceeded: true)
    }

    private var unavailable: MenuBarItemSnapshot {
        MenuBarItemSnapshot(items: [], capabilities: MenuBarOrganizerCapabilities(canEnumerate: false,
            canMove: false, hasPrivateWindowList: false, unresolvedItemCount: 0), enumerationSucceeded: false)
    }

    func invalidateIdentityCache() async { await resolver.invalidate() }

    private func enumerate() async -> [MenuBarOrganizerWindowRecord]? {
        await withCheckedContinuation { continuation in
            queue.async { [bridge] in continuation.resume(returning: Self.enumerate(using: bridge)) }
        }
    }

    private static func enumerate(using bridge: MenuBarWindowServerBridge) -> [MenuBarOrganizerWindowRecord]? {
        guard AppFeature.menuBarOrganizer.isSupportedOnCurrentSystem,
              let privateIDs = bridge.menuBarWindowIDs(), !privateIDs.isEmpty,
              let raw = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements],
                kCGNullWindowID) as? [[String: Any]] else { return nil }
        let ids = Set(privateIDs)
        let mainMenuLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
        return raw.compactMap { record(from: $0, bridge: bridge) }.filter {
            ids.contains($0.windowID) && MenuBarOrganizerSupport.isMenuBarItemCandidate($0, mainMenuLevel: mainMenuLevel)
        }
    }

    @MainActor
    private static func item(_ record: MenuBarOrganizerWindowRecord, resolved: ResolvedMenuBarItemIdentity,
                             section: MenuBarOrganizerSection) -> ManagedMenuBarItem? {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let source = resolved.source
        guard record.ownerPID != currentPID, source?.pid != currentPID else { return nil }
        let bundle = source?.bundleIdentifier ?? record.ownerBundleIdentifier
        let title = source?.displayTitle ?? record.title
        let protected = MenuBarOrganizerSupport.isSystemImmovable(bundleIdentifier: bundle, title: source?.stableTitle ?? record.title)
        let icon = source.flatMap { NSRunningApplication(processIdentifier: $0.pid)?.bundleURL }
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        return ManagedMenuBarItem(id: resolved.id, windowID: record.windowID,
            ownerPID: record.ownerPID, ownerBundleIdentifier: record.ownerBundleIdentifier,
            sourcePID: source?.pid, ownerName: record.ownerName, sourceName: source?.name ?? record.ownerName,
            bundleIdentifier: bundle, title: title, frame: record.frame, section: section,
            identityState: resolved.state, isMovable: resolved.state == .stable && !protected,
            isProtected: protected, image: icon)
    }

    private static func record(from dictionary: [String: Any],
                               bridge: MenuBarWindowServerBridge) -> MenuBarOrganizerWindowRecord? {
        guard let id = dictionary[kCGWindowNumber as String] as? NSNumber,
              let owner = dictionary[kCGWindowOwnerPID as String] as? NSNumber,
              let bounds = dictionary[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds) else { return nil }
        let windowID = CGWindowID(id.uint32Value)
        let pid = pid_t(owner.int32Value)
        let application = NSRunningApplication(processIdentifier: pid)
        return MenuBarOrganizerWindowRecord(windowID: windowID, ownerPID: pid,
            ownerName: dictionary[kCGWindowOwnerName as String] as? String ?? application?.localizedName ?? "",
            ownerBundleIdentifier: application?.bundleIdentifier ?? "",
            title: dictionary[kCGWindowName as String] as? String ?? "",
            frame: bridge.frame(for: windowID) ?? frame,
            layer: Int(bridge.level(for: windowID) ?? 0),
            alpha: (dictionary[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
            isOnScreen: (dictionary[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false)
    }
}

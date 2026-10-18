// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors
// AX enumeration follows Thaw's GPLv3 macos-27-preview.5 approach, revision
// 528b9503b051cc1ccccae766014e64404670088b. No synthetic WindowServer calls.

import AppKit

enum MenuBarNativeAXProvider {
    struct Record: Sendable {
        let publisher: MenuBarItemSourceResolver.ApplicationRecord
        let item: MenuBarItemSourceResolver.AXItemRecord
    }

    static func snapshot(includingOwn: Bool = false) async -> MenuBarItemSnapshot {
        guard AXIsProcessTrusted() else { return unavailable }
        let (applications, _) = await MenuBarItemSourceResolver.runningApplications()
        let worker = Task.detached(priority: .utility) { scan(applications) }
        let records = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
        guard let records else { return unavailable }
        return await MainActor.run { assemble(records, includingOwn: includingOwn) }
    }

    private static func scan(_ applications: [MenuBarItemSourceResolver.ApplicationRecord]) -> [Record]? {
        var records: [Record] = []
        let deadline = Date().addingTimeInterval(8)
        for app in applications {
            guard !Task.isCancelled, Date() < deadline else { return nil }
            records += MenuBarItemSourceResolver.scanExtrasMenuBar(app, trace: nil, includeNestedMetadata: true).map {
                Record(publisher: app, item: $0)
            }
        }
        guard records.contains(where: { $0.publisher.bundleIdentifier == "com.apple.MenuBarAgent" }) else { return nil }
        return records
    }

    @MainActor
    private static func assemble(_ records: [Record], includingOwn: Bool) -> MenuBarItemSnapshot {
        let direct = records.filter { $0.publisher.bundleIdentifier != "com.apple.MenuBarAgent" }
        let unique = records.filter { record in
            record.publisher.bundleIdentifier != "com.apple.MenuBarAgent" || !direct.contains {
                MenuBarNativeItemPolicy.sameFrame($0.item.frame, record.item.frame)
            }
        }.filter { includingOwn || ($0.publisher.pid != ProcessInfo.processInfo.processIdentifier
            && $0.publisher.bundleIdentifier != Bundle.main.bundleIdentifier) }
        let counts = Dictionary(grouping: unique, by: { $0.publisher.bundleIdentifier }).mapValues(\.count)
        let items = unique.compactMap { item($0, count: counts[$0.publisher.bundleIdentifier] ?? 0) }
            .sorted { $0.frame.minX < $1.frame.minX }
        let duplicates = Dictionary(grouping: items, by: \.id)
        guard duplicates.values.allSatisfy({ $0.count == 1 }) else { return unavailable }
        return MenuBarItemSnapshot(items: items, capabilities: .init(canEnumerate: true,
            canMove: false, hasPrivateWindowList: false,
            unresolvedItemCount: items.filter { $0.identityState == .provisional }.count), enumerationSucceeded: true)
    }

    @MainActor
    private static func item(_ record: Record, count: Int) -> ManagedMenuBarItem? {
        let frame = record.item.frame
        guard frame.width > 0, frame.height > 0, frame.height <= 40, isInMenuRow(frame) else { return nil }
        let source = record.item.source
        let bundle = record.publisher.bundleIdentifier
        let stableTitle = MenuBarNativeItemPolicy.title(source, publisher: bundle, count: count)
        let title = stableTitle ?? "@aster.unresolved:\(record.publisher.pid):\(frame.minX):\(frame.minY)"
        let identity = MenuBarItemIdentity(bundleIdentifier: bundle, title: title, occurrence: 0)
        let protected = MenuBarNativeItemPolicy.isPinned(bundle: bundle, title: source.displayTitle ?? title)
            || MenuBarNativeItemPolicy.isPinned(bundle: bundle, title: title)
        let icon = NSRunningApplication(processIdentifier: record.publisher.pid)?.bundleURL
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        return ManagedMenuBarItem(id: identity, windowID: MenuBarNativeItemPolicy.slot(identity),
            ownerPID: source.pid, ownerBundleIdentifier: "com.apple.MenuBarAgent",
            sourcePID: record.publisher.pid, ownerName: record.publisher.name,
            sourceName: record.publisher.name, bundleIdentifier: bundle,
            title: source.displayTitle ?? title, frame: frame, section: .visible,
            identityState: stableTitle == nil ? .provisional : .stable, isMovable: false, isProtected: protected, image: icon)
    }

    @MainActor
    private static func isInMenuRow(_ frame: CGRect) -> Bool {
        NSScreen.screens.contains { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { return false }
            let bounds = CGDisplayBounds(id)
            return bounds.contains(CGPoint(x: frame.midX, y: frame.midY)) && abs(frame.minY - bounds.minY) <= 12
        }
    }

    private static var unavailable: MenuBarItemSnapshot {
        .init(items: [], capabilities: .unavailable, enumerationSucceeded: false)
    }
}

enum MenuBarNativeItemPolicy {
    static func sameFrame(_ first: CGRect, _ second: CGRect) -> Bool {
        abs(first.minX - second.minX) < 1 && abs(first.minY - second.minY) < 1
            && abs(first.width - second.width) < 1 && abs(first.height - second.height) < 1
    }

    static func title(_ source: MenuBarItemSourceIdentity, publisher: String, count: Int) -> String? {
        if publisher == "com.apple.MenuBarAgent" { return source.axIdentifier ?? source.stableTitle }
        if count == 1 { return "@aster.single-status-item" }
        guard let identifier = source.axIdentifier, !identifier.hasPrefix("_NS:") else { return nil }
        return identifier
    }

    static func isPinned(bundle: String, title: String) -> Bool {
        bundle == "com.apple.MenuBarAgent" && ["com.apple.menuextra.clock",
            "com.apple.menuextra.controlcenter", "com.apple.menuextra.siri"].contains(title)
            || bundle == "com.apple.systemuiserver" && title.localizedCaseInsensitiveContains("siri")
    }

    /// A stable UI slot, never a WindowServer ID or an event destination.
    static func slot(_ identity: MenuBarItemIdentity) -> CGWindowID {
        identity.storageValue.utf8.reduce(UInt32(2_166_136_261)) { ($0 ^ UInt32($1)) &* 16_777_619 } | 0x8000_0000
    }
}

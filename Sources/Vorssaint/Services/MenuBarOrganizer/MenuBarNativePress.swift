// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import AppKit

enum MenuBarNativePress {
    static func press(_ item: ManagedMenuBarItem) async throws {
        guard AXIsProcessTrusted(), let pid = item.sourcePID,
              let app = await MainActor.run(body: { NSRunningApplication(processIdentifier: pid) }),
              app.bundleIdentifier == item.bundleIdentifier else { throw MenuBarItemMoveError.itemUnavailable }
        let identity = item.id
        let succeeded = await Task.detached(priority: .userInitiated) { press(identity, pid: pid) }.value
        guard succeeded else { throw MenuBarItemMoveError.itemUnavailable }
    }

    private static func press(_ identity: MenuBarItemIdentity, pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        guard let bar: AXUIElement = read("AXExtrasMenuBar", from: app),
              let children: [AXUIElement] = read(kAXChildrenAttribute, from: bar) else { return false }
        for child in children.prefix(64) {
            let nested: [AXUIElement] = read(kAXChildrenAttribute, from: child) ?? []
            let elements = [child] + nested.prefix(16)
            let matches = identity.title == "@aster.single-status-item" ? children.count == 1 : elements.contains {
                let identifier: String? = read(kAXIdentifierAttribute, from: $0)
                return identifier == identity.title
            }
            if matches { return elements.contains { AXUIElementPerformAction($0, kAXPressAction as CFString) == .success } }
        }
        return false
    }

    private static func read<T>(_ name: String, from element: AXUIElement) -> T? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value as? T : nil
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import AppKit

/// A read-only command-line probe. It creates no status items, posts no events,
/// registers no preferences and never asks macOS to grant a permission.
enum MenuBarInventoryProbe {
    static func runAndExit() -> Never {
        Task { @MainActor in
            let supported = AppFeature.menuBarOrganizer.isSupportedOnCurrentSystem
            let snapshot = supported ? await MenuBarWindowProvider().snapshot(
                hiddenDividerMidX: nil, alwaysHiddenDividerMidX: nil, excludedWindowIDs: []) : nil
            let result: [String: Any] = [
                "os": ProcessInfo.processInfo.operatingSystemVersionString,
                "supported": supported, "accessibility": AXIsProcessTrusted(),
                "enumerationSucceeded": snapshot?.enumerationSucceeded ?? false,
                "privateWindowList": snapshot?.capabilities.hasPrivateWindowList ?? false,
                "displayCount": NSScreen.screens.count,
                "conflicts": MenuBarManagerDetection.runningManagers().map(\.name),
                "items": snapshot?.items.map(describe) ?? [],
            ]
            if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]),
               let string = String(data: data, encoding: .utf8) { print(string) }
            exit(snapshot?.enumerationSucceeded == true ? 0 : 2)
        }
        RunLoop.main.run()
        exit(3)
    }

    private static func describe(_ item: ManagedMenuBarItem) -> [String: Any] {
        ["name": item.displayName, "bundleIdentifier": item.bundleIdentifier,
         "title": item.title, "windowID": item.windowID, "hostPID": item.ownerPID,
         "sourcePID": item.sourcePID ?? 0, "identity": item.identityState.rawValue,
         "movable": item.isMovable, "protected": item.isProtected,
         "frame": [item.frame.minX, item.frame.minY, item.frame.width, item.frame.height]]
    }
}

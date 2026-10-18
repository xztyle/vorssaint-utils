// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import AppKit

/// A read-only command-line probe. It creates no status items, posts no events,
/// never asks macOS to grant a permission. It may renew the same existing
/// file bookmark after Apple's atomic replacement; no access is expanded.
enum MenuBarInventoryProbe {
    static func runAndExit() -> Never {
        Task { @MainActor in
            let supported = AppFeature.menuBarOrganizer.isSupportedOnCurrentSystem
            let snapshot: MenuBarItemSnapshot?
            if #available(macOS 27, *) { snapshot = await MenuBarNativeAXProvider.snapshot() }
            else {
                snapshot = supported ? await MenuBarWindowProvider().snapshot(
                    hiddenDividerMidX: nil, alwaysHiddenDividerMidX: nil, excludedWindowIDs: []) : nil
            }
            let result: [String: Any] = [
                "os": ProcessInfo.processInfo.operatingSystemVersionString,
                "supported": supported, "accessibility": AXIsProcessTrusted(),
                "backend": ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27 ? "native-ax-read-only" : "window-server",
                "enumerationSucceeded": snapshot?.enumerationSucceeded ?? false,
                "privateWindowList": snapshot?.capabilities.hasPrivateWindowList ?? false,
                "displayCount": NSScreen.screens.count,
                "conflicts": MenuBarManagerDetection.runningManagers().map(\.name),
                "items": snapshot?.items.map(describe) ?? [],
                "nativeLayout": nativeLayout(),
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
         "title": item.title, "identityTitle": item.id.title, "windowID": item.windowID, "hostPID": item.ownerPID,
         "sourcePID": item.sourcePID ?? 0, "identity": item.identityState.rawValue,
         "movable": item.isMovable, "protected": item.isProtected,
         "frame": [item.frame.minX, item.frame.minY, item.frame.width, item.frame.height]]
    }

    @MainActor
    private static func nativeLayout() -> [String: Any] {
        guard #available(macOS 27, *) else { return ["applicable": false] }
        do {
            let document = try MenuBarNativeLayoutAccess.shared.read()
            return ["access": true, "positions": document.positions,
                    "preferenceCacheMatches": (try? MenuBarNativeLayoutAccess.shared.cacheMatches(document)) ?? false]
        } catch {
            let error = error as NSError
            return ["access": false, "errorDomain": error.domain, "errorCode": error.code]
        }
    }
}

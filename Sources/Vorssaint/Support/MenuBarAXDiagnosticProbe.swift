// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Launch through the signed app bundle to measure that GUI app's permission
/// context. No ordinary delegate, status controls, windows or input events run.
enum MenuBarAXDiagnosticProbe {
    static func runIfRequested() {
        guard CommandLine.arguments.contains(where: { $0.hasPrefix("--menu-bar-ax-diagnostics=") }) else { return }
        guard MenuBarAXDiagnosticTrace.destination != nil else { exit(2) }
        let app = NSApplication.shared
        let delegate = MenuBarAXDiagnosticDelegate()
        app.setActivationPolicy(.prohibited)
        app.delegate = delegate
        app.run()
        exit(0)
    }
}

private final class MenuBarAXDiagnosticDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.35)
        Task { @MainActor in
            guard let destination = MenuBarAXDiagnosticTrace.destination else { NSApp.terminate(nil); return }
            if AppFeature.menuBarOrganizer.isSupportedOnCurrentSystem && AXIsProcessTrusted() {
                _ = await MenuBarWindowProvider().snapshot(hiddenDividerMidX: nil,
                    alwaysHiddenDividerMidX: nil, excludedWindowIDs: [])
            }
            if !FileManager.default.fileExists(atPath: destination.path) {
                MenuBarAXDiagnosticTrace(destination: destination, records: [], guiRunning: NSApp.isRunning).finish(matches: [:])
            }
            NSApp.terminate(nil)
        }
    }
}

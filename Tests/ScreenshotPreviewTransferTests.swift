// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import AppKit

/// Exercises the production drag completion callback. Only AppKit's session
/// and modifier snapshot are substituted; no cross-app drop is claimed here.
enum ScreenshotPreviewTransferTests {
    struct NSDraggingSession {}
    enum NSEvent {
        static var modifierFlags: AppKit.NSEvent.ModifierFlags = []
        static var removedMonitors = 0
        static func removeMonitor(_ monitor: Any) { removedMonitors += 1 }
    }

    class State {
        var down: Int? = 1
        var started = true
        var cancelled = false
        var escapeMonitor: Any? = 1
        var dragging: ((Bool) -> Void)?
        var dismiss: (() -> Void)?
    }

    static func run(_ suite: TestSuite) {
        defer { NSEvent.modifierFlags = []; NSEvent.removedMonitors = 0 }
        check(suite, operation: .copy, cancelled: false, keep: false, closes: true)
        check(suite, operation: .copy, cancelled: false, keep: true, closes: false)
        check(suite, operation: [], cancelled: false, keep: false, closes: false)
        check(suite, operation: .copy, cancelled: true, keep: false, closes: false)
        let neverStarted = Surface()
        neverStarted.started = false
        var closed = false
        neverStarted.dismiss = { closed = true }
        neverStarted.draggingSession(NSDraggingSession(), endedAt: .zero, operation: .copy)
        suite.expect(!closed, "a completion without a started transfer does not discard the capture")
    }

    private static func check(_ suite: TestSuite, operation: NSDragOperation,
                              cancelled: Bool, keep: Bool, closes: Bool) {
        NSEvent.modifierFlags = keep ? [.option] : []
        NSEvent.removedMonitors = 0
        let preview = Surface()
        preview.cancelled = cancelled
        var callbacks: [String] = []
        preview.dragging = { callbacks.append($0 ? "dragging" : "released") }
        preview.dismiss = { callbacks.append("closed") }
        preview.draggingSession(NSDraggingSession(), endedAt: .zero, operation: operation)
        let context = "operation=\(operation.rawValue), cancelled=\(cancelled), option=\(keep)"
        suite.expect(callbacks == (closes ? ["released", "closed"] : ["released"]),
                     "drag completion preserves or dismisses after releasing interaction: \(context)")
        suite.expect(!preview.started && preview.down == nil && preview.escapeMonitor == nil,
                     "drag completion clears the session so the retained card remains usable: \(context)")
        suite.expect(NSEvent.removedMonitors == 1, "drag completion removes its Escape monitor: \(context)")
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import AppKit
import Carbon.HIToolbox

/// Runs the production registered callback with real, unposted AppKit key
/// events and hidden panels. The monitor registration is captured, not installed.
enum ScreenshotPreviewKeyboardTests {
    enum NSEvent {
        typealias ModifierFlags = AppKit.NSEvent.ModifierFlags
        static var callback: ((AppKit.NSEvent) -> AppKit.NSEvent?)?
        static func addLocalMonitorForEvents(matching: AppKit.NSEvent.EventTypeMask,
                                            handler: @escaping (AppKit.NSEvent) -> AppKit.NSEvent?) -> Any? {
            callback = handler
            return 1
        }
    }

    enum ShortcutCapture { static var isCapturing = false }
    final class NotchService {
        static let shared = NotchService()
        var visible = true
        func isCaptureVisible(id: UUID) -> Bool { visible }
    }

    final class Panel: NSPanel {
        var fixtureVisible = true
        override var isVisible: Bool { fixtureVisible }
    }

    enum Action: Equatable { case edit, copy, save, discard }
    class State {
        var closed = false
        var dragging = false
        var swiping = false
        var shownInNotch = false
        let presentationID = UUID()
        var keyMonitor: Any?
        var actions: [Action] = []
        func close() { closed = true }
        func perform(_ action: Action) { actions.append(action) }
    }

    static func run(_ suite: TestSuite) {
        defer {
            NSEvent.callback = nil
            ShortcutCapture.isCapturing = false
            NotchService.shared.visible = true
        }
        for gesture in ["drag", "swipe"] { checkGesture(suite, gesture: gesture) }
        checkIdleCommands(suite)
        checkOwnership(suite)
    }

    private static func panel() -> Panel {
        let panel = Panel(contentRect: NSRect(x: 0, y: 0, width: 20, height: 20),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        return panel
    }

    private static func key(_ code: Int, panel: NSPanel,
                            flags: AppKit.NSEvent.ModifierFlags = [], text: String = "") -> AppKit.NSEvent {
        AppKit.NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                               timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                               characters: text, charactersIgnoringModifiers: text,
                               isARepeat: false, keyCode: UInt16(code))!
    }

    private static func checkGesture(_ suite: TestSuite, gesture: String) {
        let controller = Controller()
        let panel = panel()
        controller.installKeyMonitor(for: panel)
        controller.dragging = gesture == "drag"
        controller.swiping = gesture == "swipe"
        let events = [key(kVK_Escape, panel: panel), key(kVK_Return, panel: panel),
                      key(kVK_Delete, panel: panel), key(kVK_ANSI_W, panel: panel, flags: .command, text: "w"),
                      key(kVK_ANSI_C, panel: panel, flags: .command, text: "c")]
        for event in events {
            suite.expect(NSEvent.callback?(event) === event && !controller.closed && controller.actions.isEmpty,
                         "\(gesture) owns key \(event.keyCode); the preview remains available")
        }
        controller.dragging = false
        controller.swiping = false
        suite.expect(NSEvent.callback?(key(kVK_Return, panel: panel)) == nil && controller.actions == [.edit],
                     "the retained preview can be edited after cancelling \(gesture)")
    }

    private static func checkIdleCommands(_ suite: TestSuite) {
        let panel = panel()
        let commands: [(Int, AppKit.NSEvent.ModifierFlags, String, Action?)] = [
            (kVK_Escape, [], "", nil), (kVK_ANSI_W, .command, "w", nil),
            (kVK_Return, [], "", .edit), (kVK_Delete, [], "", .discard),
            (kVK_ANSI_C, .command, "c", .copy), (kVK_ANSI_S, .command, "s", .save)]
        for (code, flags, text, action) in commands {
            let controller = Controller()
            controller.installKeyMonitor(for: panel)
            suite.expect(NSEvent.callback?(key(code, panel: panel, flags: flags, text: text)) == nil,
                         "idle preview handles key \(code)")
            suite.expect(controller.closed == (action == nil) && controller.actions == (action.map { [$0] } ?? []),
                         "idle preview performs only the requested action for key \(code)")
        }
    }

    private static func checkOwnership(_ suite: TestSuite) {
        let panel = panel()
        let foreign = self.panel()
        let controller = Controller()
        controller.installKeyMonitor(for: panel)
        let escape = key(kVK_Escape, panel: panel)
        suite.expect(NSEvent.callback?(key(kVK_Escape, panel: foreign)) != nil && !controller.closed,
                     "another window retains its Escape key")
        panel.fixtureVisible = false
        suite.expect(NSEvent.callback?(escape) === escape && !controller.closed, "hidden previews do not take Escape")
        panel.fixtureVisible = true
        ShortcutCapture.isCapturing = true
        suite.expect(NSEvent.callback?(escape) === escape && !controller.closed, "shortcut recording retains Escape")
        ShortcutCapture.isCapturing = false
        controller.shownInNotch = true
        NotchService.shared.visible = false
        suite.expect(NSEvent.callback?(escape) === escape && !controller.closed, "hidden notch captures retain Escape")
        NotchService.shared.visible = true
    }
}

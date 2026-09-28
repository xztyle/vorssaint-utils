// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import Foundation

/// Runs production paste routing with controlled focus and permission changes.
enum ClipboardQuickPasteTests {
    final class Host {
        final class App {
            let processIdentifier: Int32 = 42
            let isTerminated: Bool
            init(isTerminated: Bool) { self.isTerminated = isTerminated }
            func activate(options: [Int]) {
                Host.host?.events.append("activate")
                if Host.host?.activationChecksUntilFocused ?? 0 > 0 {
                    Host.host?.pendingFrontmost = self
                } else { Host.host?.frontmost = self }
            }
        }

        typealias NSRunningApplication = App
        enum ClipboardLibraryProbe { static var root: URL? { nil } }
        final class Workspace {
            static let shared = Workspace()
            var frontmostApplication: App? {
                if let host = Host.host, host.activationChecksUntilFocused > 0 {
                    host.activationChecksUntilFocused -= 1
                    if host.activationChecksUntilFocused == 0 {
                        host.frontmost = host.pendingFrontmost
                        host.pendingFrontmost = nil
                    }
                }
                return Host.host?.frontmost
            }
        }
        typealias NSWorkspace = Workspace
        enum Sound { static func beep() { Host.host?.events.append("beep") } }
        typealias NSSound = Sound
        final class Access {
            static let shared = Access()
            func requestAccessibility() { Host.host?.events.append("prompt") }
        }
        typealias Permissions = Access
        final class Queue {
            static let main = Queue()
            func asyncAfter(deadline: DispatchTime, execute work: @escaping () -> Void) {
                if Host.host?.switchBeforePaste == true { Host.host?.frontmost = nil }
                work()
            }
        }
        typealias DispatchQueue = Queue

        static var host: Host?
        var frontmost: App?
        var pendingFrontmost: App?
        var activationChecksUntilFocused = 0
        var switchBeforePaste = false
        var events: [String] = []
        var trusted = true
        var promptedForAccessibility = false
        init() { Self.host = self }
        func AXIsProcessTrusted() -> Bool { trusted }
        static func postPasteShortcut() { host?.events.append("paste") }
    }

    static func run(_ suite: TestSuite) {
        permissionCases(suite)
        focusCases(suite)
        missingTargetCases(suite)
    }

    private static func permissionCases(_ suite: TestSuite) {
        for (terminated, trusted, expected) in [
            (true, true, ["beep"]),
            (false, false, ["activate", "prompt", "activate", "beep"]),
            (false, true, ["activate", "paste"]),
        ] {
            let host = Host()
            host.trusted = trusted
            let app = Host.App(isTerminated: terminated)
            host.pasteIntoPreviousApp(app)
            if !trusted { host.pasteIntoPreviousApp(app) }
            suite.expect(host.events == expected,
                         "quick paste permission and termination flow: \(host.events)")
        }
    }

    private static func focusCases(_ suite: TestSuite) {
        let switched = Host()
        switched.switchBeforePaste = true
        switched.pasteIntoPreviousApp(Host.App(isTerminated: false))
        suite.expect(switched.events == ["activate", "beep"],
                     "focus change during paste delay sends no global keystroke")
        let delayed = Host()
        delayed.activationChecksUntilFocused = 3
        delayed.pasteIntoPreviousApp(Host.App(isTerminated: false))
        suite.expect(delayed.events == ["activate", "paste"],
                     "quick paste waits for slower activation and posts exactly once")
        let neverFocused = Host()
        neverFocused.activationChecksUntilFocused = 20
        neverFocused.pasteIntoPreviousApp(Host.App(isTerminated: false))
        suite.expect(neverFocused.events == ["activate", "beep"],
                     "quick paste gives up without a keystroke when focus never returns")
    }

    private static func missingTargetCases(_ suite: TestSuite) {
        for trusted in [true, false] {
            let host = Host()
            host.trusted = trusted
            host.pasteIntoPreviousApp(nil)
            suite.expect(host.events.isEmpty,
                         "quick paste with no target stays a silent copy: \(host.events)")
        }
    }
}

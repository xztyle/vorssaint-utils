// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import AppKit

/// The generated host compiles the production pointer-cleanup body against
/// inert cursor and transport endpoints. No input or cursor changes are sent.
enum MenuBarPointerRecoveryTests {
    class Fixture {
        enum MenuBarItemMoveError: Error { case verificationFailed }
        var events: [String] = []
        var dragFails = false
        var settles = true
        var releaseConfirmed = true
        static func activeDisplays() -> [CGDirectDisplayID] { [1] }
        func mouseLocation(_ item: ManagedMenuBarItem) -> CGPoint { CGPoint(x: 703, y: 1229) }
        @discardableResult func CGDisplayHideCursor(_ display: CGDirectDisplayID) -> CGError { events.append("hide"); return .success }
        @discardableResult func CGDisplayShowCursor(_ display: CGDirectDisplayID) -> CGError { events.append("show"); return .success }
        @discardableResult func CGWarpMouseCursorPosition(_ point: CGPoint) -> CGError { events.append("warp"); return .success }
        @discardableResult func CGAssociateMouseAndMouseCursorPosition(_ connected: boolean_t) -> CGError {
            events.append(connected == 0 ? "disconnect" : "connect"); return .success
        }
        func postCommandDrag(item: ManagedMenuBarItem, to: CGPoint) async throws {
            events.append("drag")
            if dragFails { throw MenuBarItemMoveError.verificationFailed }
        }
        func waitForRestingFrame(_ item: ManagedMenuBarItem) async -> Bool { events.append("settle"); return settles }
        func recoverRelease(_ item: ManagedMenuBarItem, at: CGPoint) async -> Bool {
            events.append("release-confirmation"); return releaseConfirmed
        }
    }

    static func run(_ suite: TestSuite) {
        let failed = Host(); failed.dragFails = true
        execute(failed)
        suite.expect(failed.events == ["hide", "disconnect", "drag", "release-confirmation", "warp", "connect", "show"],
                     "a failed drag awaits release confirmation before restoring the old pointer")
        let uncertain = Host(); uncertain.dragFails = true; uncertain.releaseConfirmed = false
        execute(uncertain)
        suite.expect(!uncertain.events.contains("warp") && uncertain.events.suffix(2) == ["connect", "show"],
                     "failed release never carries the held icon to the old pointer, but returns visible cursor control")
        let transient = Host(); transient.settles = false; transient.releaseConfirmed = false
        execute(transient)
        suite.expect(transient.events.contains("release-confirmation") && !transient.events.contains("warp"),
                     "an acknowledged drag with an off-row transient frame must recover before cursor restoration")
        let success = Host(); execute(success)
        suite.expect(success.events == ["hide", "disconnect", "drag", "settle", "warp", "connect", "show"],
                     "successful input still waits for stable window geometry before restoring the pointer")
    }

    static func execute(_ host: Host) {
        var finished = false
        Task { @MainActor in
            try? await host.dragWithCursor(MenuBarOrganizerTests.item("A", x: 10), to: .zero)
            finished = true
        }
        let deadline = Date().addingTimeInterval(2)
        while !finished, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.002)) }
    }
}

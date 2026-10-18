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
        func postCommandDrag(item: ManagedMenuBarItem, to: CGPoint, destinationWindowID: CGWindowID,
                             after: Bool = false, usesWindowRouting: Bool = false) async throws {
            events.append("drag")
            if dragFails { throw MenuBarItemMoveError.verificationFailed }
        }
        func waitForRestingFrame(_ item: ManagedMenuBarItem) async -> Bool { events.append("settle"); return settles }
        func recoverRelease(_ item: ManagedMenuBarItem, at: CGPoint) async -> Bool {
            events.append("release-confirmation"); return releaseConfirmed
        }
    }

    static func run(_ suite: TestSuite) {
        routedTransaction(suite)
        MenuBarVisibleDragTests.run(suite)
        let failed = Host(); failed.dragFails = true
        execute(failed)
        suite.expect(failed.events == ["hide", "drag", "release-confirmation", "warp", "show"],
                     "a failed drag awaits release confirmation before restoring the old pointer")
        let uncertain = Host(); uncertain.dragFails = true; uncertain.releaseConfirmed = false
        execute(uncertain)
        suite.expect(uncertain.events == ["hide", "drag", "release-confirmation", "show"],
                     "failed release never carries the held icon to the old pointer, but returns visible cursor control")
        let transient = Host(); transient.settles = false; transient.releaseConfirmed = false
        execute(transient)
        suite.expect(transient.events.contains("release-confirmation") && !transient.events.contains("warp"),
                     "an acknowledged drag with an off-row transient frame must recover before cursor restoration")
        let success = Host(); execute(success)
        suite.expect(success.events == ["hide", "drag", "settle", "warp", "show"],
                     "posted drags keep cursor association and wait for stable geometry before restoring the pointer")
    }

    static func execute(_ host: Host) {
        var finished = false
        Task { @MainActor in
            try? await host.dragWithCursor(MenuBarOrganizerTests.item("A", x: 10), to: .zero, destinationWindowID: 2)
            finished = true
        }
        let deadline = Date().addingTimeInterval(2)
        while !finished, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.002)) }
    }

    static func routedTransaction(_ suite: TestSuite) {
        let trace = executeMove(failure: nil)
        let source = MenuBarOrganizerTests.item("Siri", x: 1711)
        let destinationID = source.windowID + 100
        suite.expect(trace.events.map(\.type) == [.leftMouseDown, .leftMouseUp],
                     "the production move transaction sends an acknowledged press and release")
        guard trace.events.count == 2, trace.fallback != nil else { return }
        let field = MenuBarItemEventFactory.windowField
        suite.expect(trace.events[0].getIntegerValueField(field) == Int64(source.windowID)
            && trace.events[1].getIntegerValueField(field) == Int64(destinationID),
                     "the press selects the source window and the release selects the verified destination")
        suite.expect(trace.events.allSatisfy {
            $0.getIntegerValueField(.eventTargetUnixProcessID) == Int64(source.ownerPID)
        }, "the original item's host receives both window-bound move phases")
        suite.expect(trace.events[0].location == CGPoint(x: 1815, y: 0)
            && trace.events[0].flags == .maskCommand && trace.events[1].flags.isEmpty,
                     "Thaw's window-bound press starts at the actual destination on the menu row")
        suite.expect(trace.cursorPositions == [CGPoint(x: 1815, y: 0)],
                     "the window-bound press also positions the hidden pointer at its destination")
        suite.expect(trace.events[1].location == CGPoint(x: 1777, y: 0),
                     "release follows the destination's new position after the source leaves the menu bar")
        let after = executeMove(failure: nil, after: true)
        suite.expect(after.events.last?.location == CGPoint(x: 1813, y: 0),
                     "right-side placement retains its side against the refreshed destination frame")
        fallbackTransactionRecovery(trace, source: source, suite)
    }

    static func fallbackTransactionRecovery(_ trace: MoveTrace, source: ManagedMenuBarItem, _ suite: TestSuite) {
        guard let fallback = trace.fallback else { return }
        let field = MenuBarItemEventFactory.windowField
        suite.expect(fallback.getIntegerValueField(field) == Int64(source.windowID)
            && fallback.location == MenuBarMoveGeometry.pressPoint(in: source.frame) && fallback.flags.isEmpty,
                     "interrupted delivery releases at the original position rather than completing a failed move")
        suite.expect(trace.releases == 0 && trace.order == ["start", "close"],
                     "a normal release disarms fallback and closes the relay")
        for phase in [1, 2] {
            let failed = executeMove(failure: phase)
            suite.expect(failed.releases == 1 && failed.order == ["start", "close"],
                         "failure in phase \(phase) releases once and closes the transport")
        }
        let unchanged = executeMove(failure: nil, frameUpdates: false)
        suite.expect(unchanged.events.count == 1 && unchanged.releases == 1,
                     "a host acknowledgement without real frame change aborts before destination release")
        let disappeared = executeMove(failure: nil, targetDisappears: true)
        suite.expect(disappeared.events.count == 1 && disappeared.releases == 1,
                     "a destination that disappears during the press releases at the original position")
    }

    static func executeMove(failure: Int?, frameUpdates: Bool = true,
                            after: Bool = false, targetDisappears: Bool = false, visibleDrag: Bool = false,
                            usesWindowRouting: Bool = false) -> MoveTrace {
        let trace = MoveTrace(); trace.failurePhase = failure; trace.frameUpdates = frameUpdates
        trace.targetDisappears = targetDisappears
        trace.visibleDrag = visibleDrag
        MoveFixture.MenuBarItemEventRelay.trace = trace
        let source = MenuBarOrganizerTests.item("Siri", x: 1711)
        MoveFixture.MenuBarWindowServerBridge.shared.currentFrame = source.frame
        MoveFixture.MenuBarWindowServerBridge.shared.sourceWindowID = source.windowID
        MoveFixture.MenuBarWindowServerBridge.shared.targetFrame = CGRect(x: 1814, y: 0, width: 38, height: 39)
        var finished = false
        Task { @MainActor in
            try? await MoveHost().postCommandDrag(item: source, to: CGPoint(x: 1814, y: 19.5),
                                                  destinationWindowID: source.windowID + 100, after: after,
                                                  usesWindowRouting: usesWindowRouting)
            finished = true
        }
        let deadline = Date().addingTimeInterval(2)
        while !finished, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.002)) }
        return trace
    }

    final class MoveTrace {
        var events: [CGEvent] = []
        var fallback: CGEvent?
        var releases = 0
        var failurePhase: Int?
        var frameUpdates = true
        var targetDisappears = false
        var visibleDrag = false
        var cursorPositions: [CGPoint] = []
        var visibleMoves: [(CGPoint, CGPoint)] = []
        var order: [String] = []
    }

    class MoveFixture {
        enum MenuBarItemMoveError: Error { case eventCreationFailed, verificationFailed, itemUnavailable }
        func source() throws -> CGEventSource { MenuBarItemEventFactory.source()! }
        static func screenFrames() -> [CGRect] { [CGRect(x: 0, y: 0, width: 2058, height: 1320)] }
        static func dragRegions() -> [CGRect] { MenuBarItemEventRelay.trace.visibleDrag ? screenFrames() : [] }
        @discardableResult func CGWarpMouseCursorPosition(_ point: CGPoint) -> CGError {
            MenuBarItemEventRelay.trace.cursorPositions.append(point); return .success
        }
        func event(_ type: CGEventType, source: CGEventSource, point: CGPoint,
                   item: ManagedMenuBarItem, moving: Bool) throws -> CGEvent {
            guard let event = MenuBarItemEventFactory.make(type, source: source, point: point,
                windowID: item.windowID, targetPID: targetPID(item), moving: moving)
            else { throw MenuBarItemMoveError.eventCreationFailed }
            return event
        }
        func targetPID(_ item: ManagedMenuBarItem) -> pid_t { item.ownerPID }
        func checkFrame(_ item: ManagedMenuBarItem) throws { }
        func releaseGuard(_ event: CGEvent, pid: pid_t) throws -> MenuBarPressReleaseGuard {
            let trace = MenuBarItemEventRelay.trace
            trace.fallback = event.copy()
            return MenuBarPressReleaseGuard { trace.releases += 1 }
        }
        final class MenuBarVisibleDragTransport {
            func drag(from start: CGPoint, region: CGRect, validateSource: () throws -> Void,
                      destination: () throws -> CGPoint) async throws {
                try validateSource()
                let end = try destination()
                MenuBarItemEventRelay.trace.visibleMoves.append((start, end))
            }
        }
        final class MenuBarItemEventRelay {
            static var trace = MoveTrace()
            init(pid: pid_t) {}
            func start() throws { Self.trace.order.append("start") }
            func close() { Self.trace.order.append("close") }
            func send(_ event: CGEvent, press: MenuBarPressReleaseGuard) async throws {
                Self.trace.events.append(event.copy()!)
                if Self.trace.events.count == Self.trace.failurePhase { throw MenuBarItemMoveError.verificationFailed }
                if Self.trace.frameUpdates {
                    MenuBarWindowServerBridge.shared.currentFrame?.origin = event.location
                    if event.type == .leftMouseDown {
                        MenuBarWindowServerBridge.shared.targetFrame = Self.trace.targetDisappears ? nil
                            : CGRect(x: 1776, y: 0, width: 38, height: 39)
                    }
                }
            }
        }
        final class MenuBarWindowServerBridge {
            static let shared = MenuBarWindowServerBridge()
            var currentFrame: CGRect?
            var targetFrame: CGRect?
            var sourceWindowID: CGWindowID = 0
            func frame(for windowID: CGWindowID) -> CGRect? {
                windowID == sourceWindowID ? currentFrame : targetFrame
            }
        }
    }
}

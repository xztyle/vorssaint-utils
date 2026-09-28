// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import CoreGraphics

/// Inspect the actual CoreGraphics events without posting input to any process.
enum MenuBarItemEventTests {
    static func run(_ suite: TestSuite) {
        guard let source = MenuBarItemEventFactory.source() else {
            suite.expect(false, "menu event source can be created"); return
        }
        for type: CGEventType in [.leftMouseDown, .leftMouseDragged, .leftMouseUp] {
            routing(type, source: source, suite: suite)
        }
        click(source, suite)
        invalidTargets(source, suite)
        deliveryHandshake(suite)
        deliveryRejection(suite)
        releaseRecovery(suite)
        releaseOrdering(suite)
        hoverRouting(source, suite)
    }

    static func routing(_ type: CGEventType, source: CGEventSource, suite: TestSuite) {
        let destination = CGPoint(x: 1751, y: 19.5)
        guard let event = MenuBarItemEventFactory.make(type, source: source, point: destination,
            windowID: 2611, targetPID: 625, moving: true) else {
            suite.expect(false, "verified remote status item creates a move event"); return
        }
        suite.expect(event.type == type && event.location == destination, "routing preserves the requested gesture and destination")
        suite.expect(event.getIntegerValueField(.eventTargetUnixProcessID) == 625,
                     "Docker hosted by Control Center targets the host, not the source app")
        for field: CGEventField in [.mouseEventWindowUnderMousePointer,
            .mouseEventWindowUnderMousePointerThatCanHandleThisEvent, MenuBarItemEventFactory.windowField] {
            suite.expect(event.getIntegerValueField(field) == 2611,
                         "every move phase keeps the original window even when its point crosses other icons")
        }
        suite.expect(event.flags == (type == .leftMouseUp ? [] : .maskCommand),
                     "press and drag hold Command; release clears synthetic modifiers")
        suite.expect(event.getIntegerValueField(.mouseEventClickState) == (type == .leftMouseUp ? 0 : 1),
                     "release cannot leave a synthetic click held")
    }

    static func click(_ source: CGEventSource, _ suite: TestSuite) {
        for type: CGEventType in [.leftMouseDown, .leftMouseUp] {
            let event = MenuBarItemEventFactory.make(type, source: source, point: CGPoint(x: 1430, y: 18),
                windowID: 42, targetPID: 625, moving: false)
            suite.expect(event?.flags.isEmpty == true, "activation never becomes a Command-drag")
            suite.expect(event?.getIntegerValueField(.mouseEventWindowUnderMousePointer) == 42,
                         "activation is bound to the intended hosted status window")
        }
    }

    static func invalidTargets(_ source: CGEventSource, _ suite: TestSuite) {
        for (window, pid, point) in [(UInt32(0), Int32(625), CGPoint.zero),
            (42, 0, .zero), (42, -1, .zero), (42, 625, CGPoint(x: CGFloat.nan, y: 0)),
            (42, 625, CGPoint(x: 0, y: CGFloat.infinity))] {
            suite.expect(MenuBarItemEventFactory.make(.leftMouseDown, source: source, point: point,
                windowID: window, targetPID: pid, moving: true) == nil, "invalid routing cannot create an input event")
        }
        suite.expect(MenuBarItemEventFactory.make(.keyDown, source: source, point: .zero,
            windowID: 42, targetPID: 625, moving: true) == nil, "unexpected input types fail closed")
    }

    static func deliveryHandshake(_ suite: TestSuite) {
        var state = MenuBarEventDeliveryState(entryToken: 1, mouseToken: 2, exitToken: 3)
        suite.expect(state.receive(token: 99, isSession: false, matchesWindow: false) == .pass
            && state.phase == .entry, "another application's input never starts a synthetic gesture")
        suite.expect(state.receive(token: 1, isSession: true, matchesWindow: false) == .pass,
                     "session input cannot impersonate a target-process entry")
        suite.expect(state.receive(token: 1, isSession: false, matchesWindow: false) == .sendToSession,
                     "the target acknowledges entry before the gesture enters the system stream")
        suite.expect(state.receive(token: 2, isSession: false, matchesWindow: true) == .pass,
                     "process-only delivery does not count as a completed move")
        suite.expect(state.receive(token: 2, isSession: true, matchesWindow: true) == .sendToTarget,
                     "the exact session event is relayed to its window host")
        suite.expect(state.receive(token: 3, isSession: false, matchesWindow: false) == .pass,
                     "an early exit cannot claim a gesture was delivered")
        suite.expect(state.receive(token: 2, isSession: false, matchesWindow: true) == .sendExit,
                     "host delivery queues a completion barrier behind the mouse event")
        suite.expect(state.receive(token: 3, isSession: false, matchesWindow: false) == .finish
            && state.phase == .complete, "only the host completion barrier finishes the delivery")
        suite.expect(state.receive(token: 3, isSession: false, matchesWindow: false) == .pass,
                     "duplicate acknowledgements cannot complete twice")
    }

    static func deliveryRejection(_ suite: TestSuite) {
        for inSession in [false, true] {
            var state = MenuBarEventDeliveryState(entryToken: 1, mouseToken: 2, exitToken: 3)
            _ = state.receive(token: 1, isSession: false, matchesWindow: false)
            suite.expect(state.receive(token: 2, isSession: inSession, matchesWindow: false) == .reject,
                         "our event rebound to another window is dropped in either stream")
            suite.expect(state.receive(token: 3, isSession: false, matchesWindow: true) == .pass
                && state.phase == .failed, "a wrong-window failure cannot later report success")
        }
    }

    static func releaseRecovery(_ suite: TestSuite) {
        var releases = 0
        let interrupted = MenuBarPressReleaseGuard { releases += 1 }
        interrupted.releaseIfArmed(); interrupted.releaseIfArmed()
        suite.expect(releases == 1, "timeout and cancellation racing each other release the held button once")
        var posted = 0
        suite.expect(!interrupted.isArmed && !interrupted.performIfArmed { posted += 1 } && posted == 0,
                     "a watchdog release prevents all later mouse delivery, even before a waiter resumes")
        let completed = MenuBarPressReleaseGuard { releases += 1 }
        suite.expect(completed.performIfArmed { posted += 1 } && posted == 1, "a live press permits event delivery")
        completed.confirmRelease(); completed.releaseIfArmed()
        suite.expect(releases == 1 && !completed.isArmed, "a confirmed normal release disarms the fallback")
    }

    static func releaseOrdering(_ suite: TestSuite) {
        let started = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        var order: [String] = []
        let guardItem = MenuBarPressReleaseGuard { order.append("release") }
        guardItem.performIfArmed {
            DispatchQueue.global().async {
                started.signal()
                guardItem.releaseIfArmed()
                finished.signal()
            }
            _ = started.wait(timeout: .now() + 1)
            suite.expect(finished.wait(timeout: .now()) == .timedOut,
                         "the watchdog cannot release between the liveness check and a mouse post")
            order.append("mouse")
        }
        suite.expect(finished.wait(timeout: .now() + 1) == .success && order == ["mouse", "release"],
                     "an in-flight post completes before watchdog release; later posts are rejected")
        suite.expect(!guardItem.performIfArmed { order.append("late drag") }, "a later drag cannot revive the released gesture")
    }

    static func hoverRouting(_ source: CGEventSource, _ suite: TestSuite) {
        for type: CGEventType in [.leftMouseDown, .leftMouseDragged, .leftMouseUp] {
            guard let expected = MenuBarItemEventFactory.make(type, source: source, point: .zero,
                windowID: 14651, targetPID: 625, moving: true), let received = expected.copy() else {
                suite.expect(false, "create routed event fixtures"); return
            }
            received.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: 14661)
            received.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: 14661)
            suite.expect(MenuBarItemEventFactory.routingMatches(received, expected: expected) == (type != .leftMouseDown),
                         "actual Tahoe hover-field changes are accepted only after a verified press")
            received.setIntegerValueField(MenuBarItemEventFactory.windowField, value: 494)
            suite.expect(!MenuBarItemEventFactory.routingMatches(received, expected: expected),
                         "a rewritten explicit target never becomes an accepted drag or release")
            received.setIntegerValueField(MenuBarItemEventFactory.windowField, value: 14651)
            received.setIntegerValueField(.eventTargetUnixProcessID, value: 626)
            suite.expect(!MenuBarItemEventFactory.routingMatches(received, expected: expected), "wrong host delivery always fails closed")
        }
        guard let click = MenuBarItemEventFactory.make(.leftMouseUp, source: source, point: .zero,
            windowID: 14651, targetPID: 625, moving: false), let changed = click.copy() else { return }
        changed.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: 494)
        suite.expect(!MenuBarItemEventFactory.routingMatches(changed, expected: click),
                     "ordinary activation does not inherit the held-drag hover exception")
    }
}

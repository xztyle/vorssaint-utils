// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import CoreGraphics

/// Replay the recorded Tahoe release without sending any input.
enum MenuBarDragReleaseTests {
    static func run(_ source: CGEventSource, _ suite: TestSuite) {
        guard let expected = MenuBarItemEventFactory.make(.leftMouseUp, source: source,
            point: CGPoint(x: 1901, y: 19.5), windowID: 24, targetPID: 625, moving: true),
              let received = expected.copy() else { suite.expect(false, "create recorded release"); return }
        received.setIntegerValueField(MenuBarItemEventFactory.windowField, value: 5139)
        for session in [false, true] {
            for verified in [false, true] {
                suite.expect(MenuBarItemEventFactory.routingMatches(received, expected: expected,
                    isSession: session, verifiedSession: verified, dragOriginWindow: 5139) == (!session && verified),
                    "recorded release requires verified session delivery and the acknowledged press origin")
            }
        }
        for origin: CGWindowID? in [nil, 0, 494, 24] {
            suite.expect(!MenuBarItemEventFactory.routingMatches(received, expected: expected,
                verifiedSession: true, dragOriginWindow: origin), "an unknown or different origin cannot authorize release")
        }
        changedFields(received, expected: expected, suite)
        changedGesture(received, expected: expected, suite)
    }

    private static func changedFields(_ received: CGEvent, expected: CGEvent, _ suite: TestSuite) {
        for (field, value): (CGEventField, Int64) in [(.eventTargetUnixProcessID, 626),
            (.mouseEventWindowUnderMousePointer, 494), (.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, 494),
            (MenuBarItemEventFactory.windowField, 494)] {
            guard let changed = received.copy() else { continue }
            changed.setIntegerValueField(field, value: value)
            suite.expect(!MenuBarItemEventFactory.routingMatches(changed, expected: expected,
                verifiedSession: true, dragOriginWindow: 5139), "release remains bound to its exact host, origin and destination")
        }
    }

    private static func changedGesture(_ received: CGEvent, expected: CGEvent, _ suite: TestSuite) {
        guard let changed = received.copy() else { return }
        changed.flags = .maskCommand
        suite.expect(!MenuBarItemEventFactory.routingMatches(changed, expected: expected,
            verifiedSession: true, dragOriginWindow: 5139), "release cannot retain a synthetic Command drag")
        changed.flags = []; changed.type = .leftMouseDown
        suite.expect(!MenuBarItemEventFactory.routingMatches(changed, expected: expected,
            verifiedSession: true, dragOriginWindow: 5139), "a release exception cannot authorize another press")
        changed.type = .leftMouseUp; changed.location.x += 20
        suite.expect(!MenuBarItemEventFactory.routingMatches(changed, expected: expected,
            verifiedSession: true, dragOriginWindow: 5139), "release exception cannot change its destination point")
    }
}

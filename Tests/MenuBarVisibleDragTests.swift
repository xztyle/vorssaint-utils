// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import CoreGraphics
import Foundation

enum MenuBarVisibleDragTests {
    static func run(_ suite: TestSuite) {
        pathGeometry(suite)
        nativeReorderGeometry(suite)
        let trace = MenuBarPointerRecoveryTests.executeMove(failure: nil, visibleDrag: true)
        let source = MenuBarOrganizerTests.item("Siri", x: 1711)
        suite.expect(trace.visibleMoves.first?.0 == MenuBarMoveGeometry.pressPoint(in: source.frame),
                     "visible routing selects the verified source's center")
        suite.expect(trace.events.isEmpty && trace.order.isEmpty,
                     "visible icons use the main input stream rather than PID-scromble delivery")
        let fixedAnchor = MenuBarPointerRecoveryTests.executeMove(failure: nil, visibleDrag: true, usesWindowRouting: true)
        suite.expect(fixedAnchor.visibleMoves.isEmpty && fixedAnchor.events.count == 2,
                     "a protected anchor uses precise window routing despite its on-screen position")
        nativeSequence(suite)
        cancellation(suite)
        modifierCancellation(suite)
        changedSource(suite)
    }

    private static func pathGeometry(_ suite: TestSuite) {
        let regions = [CGRect(x: 0, y: 0, width: 950, height: 39), CGRect(x: 1100, y: 0, width: 950, height: 39)]
        let start = CGPoint(x: 1726, y: 19.5), end = CGPoint(x: 1901, y: 19.5)
        suite.expect(MenuBarMoveGeometry.dragRegion(from: start, to: end, regions: regions) == regions[1],
                     "a visible same-segment path selects its notch-safe region")
        for point in [CGPoint(x: 500, y: 19.5), CGPoint(x: 1000, y: 19.5),
                      CGPoint(x: 2100, y: 19.5), CGPoint(x: 1901, y: 40), CGPoint(x: .nan, y: 19.5)] {
            suite.expect(MenuBarMoveGeometry.dragRegion(from: start, to: point, regions: regions) == nil,
                         "a visible drag cannot cross the notch, a display edge or a different row")
        }
    }

    private static func nativeSequence(_ suite: TestSuite) {
        var events: [CGEvent] = [], destinationReads = 0
        var complete = false
        Task { @MainActor in
            do {
                try await MenuBarVisibleDragTransport(postEvent: { events.append($0.copy()!) }).drag(
                    from: CGPoint(x: 1730, y: 19.5), region: CGRect(x: 1100, y: 0, width: 950, height: 39), validateSource: {}) {
                        destinationReads += 1
                        return CGPoint(x: destinationReads < 3 ? 1880 : 1900, y: 19.5)
                    }
            } catch { suite.expect(false, "inert drag completes: \(error)") }
            complete = true
        }
        wait { complete }
        suite.expect(complete && events.count == 16, "production transport positions, holds Command, presses, drags ten steps, refreshes the drop, then releases mouse and Command")
        suite.expect(events.first?.type == .mouseMoved && events[1].type == .flagsChanged
            && events[1].flags.contains(.maskCommand) && events[2].type == .leftMouseDown,
                     "the pointer settles before the Command press")
        suite.expect(events.dropFirst(3).dropLast(2).allSatisfy { $0.type == .leftMouseDragged && $0.flags == .maskCommand },
                     "every intermediate step keeps Command held")
        suite.expect(events.dropLast().last?.type == .leftMouseUp && events.dropLast().last?.location == CGPoint(x: 1900, y: 19.5),
                     "the release follows the fresh destination after menu reflow")
        suite.expect(events.dropLast().suffix(2).allSatisfy { $0.location == CGPoint(x: 1900, y: 19.5) && $0.flags == .maskCommand },
                     "the final drag and release both reach the refreshed drop with Command held")
        suite.expect(events.last?.type == .flagsChanged && events.last?.flags.contains(.maskCommand) == false
            && events.last?.getIntegerValueField(.keyboardEventKeycode) == 55,
                     "a completed drag releases the synthetic Command key so the next gesture can start")
        suite.expect(events.allSatisfy { $0.getIntegerValueField(MenuBarItemEventFactory.windowField) == 0 },
                     "main-input gestures let WindowServer resolve the visible window")
    }

    private static func cancellation(_ suite: TestSuite) {
        var events: [CGEvent] = [], task: Task<Void, Never>?, complete = false
        task = Task { @MainActor in
            do {
                try await MenuBarVisibleDragTransport(postEvent: {
                    events.append($0.copy()!)
                    if $0.type == .leftMouseDown { task?.cancel() }
                }).drag(from: CGPoint(x: 1730, y: 19.5), region: CGRect(x: 1100, y: 0, width: 950, height: 39), validateSource: {}) {
                    CGPoint(x: 1880, y: 19.5)
                }
                suite.expect(false, "cancelled drag cannot succeed")
            } catch { }
            complete = true
        }
        wait { complete }
        suite.expect(events.map(\.type) == [.mouseMoved, .flagsChanged, .leftMouseDown, .leftMouseUp, .flagsChanged],
                     "cancellation releases the press once and prevents all remaining drag steps")
        suite.expect(events.dropLast().last?.flags.isEmpty == true && events.dropLast().last?.location == CGPoint(x: 1730, y: 19.5),
                     "an interrupted gesture releases at its safe original position")
        suite.expect(events.last?.flags.contains(.maskCommand) == false,
                     "cancellation also releases Command instead of blocking all following gestures")
    }

    private static func wait(_ done: () -> Bool) {
        let deadline = Date().addingTimeInterval(2)
        while !done(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.002)) }
    }

    private static func modifierCancellation(_ suite: TestSuite) {
        var events: [CGEvent] = [], task: Task<Void, Never>?, complete = false
        task = Task { @MainActor in
            do {
                try await MenuBarVisibleDragTransport(postEvent: {
                    events.append($0.copy()!)
                    if $0.type == .flagsChanged && $0.flags.contains(.maskCommand) { task?.cancel() }
                }).drag(from: CGPoint(x: 1730, y: 19.5), region: CGRect(x: 1100, y: 0, width: 950, height: 39), validateSource: {}) {
                    CGPoint(x: 1880, y: 19.5)
                }
                suite.expect(false, "cancelling while Command is pressed cannot begin the mouse drag")
            } catch { }
            complete = true
        }
        wait { complete }
        suite.expect(!events.contains { $0.type == .leftMouseDown || $0.type == .leftMouseDragged },
                     "cancellation between modifier press and mouse press prevents the drag")
        suite.expect(events.last?.type == .flagsChanged && events.last?.flags.contains(.maskCommand) == false,
                     "cancellation before mouse press still releases the introduced Command state")
    }

    private static func changedSource(_ suite: TestSuite) {
        var events: [CGEvent] = [], complete = false
        Task { @MainActor in
            do {
                try await MenuBarVisibleDragTransport(postEvent: { events.append($0.copy()!) }).drag(
                    from: CGPoint(x: 1730, y: 19.5), region: CGRect(x: 1100, y: 0, width: 950, height: 39),
                    validateSource: { throw MenuBarItemMoveError.itemUnavailable }) {
                        CGPoint(x: 1880, y: 19.5)
                    }
                suite.expect(false, "a changed source cannot be pressed")
            } catch { }
            complete = true
        }
        wait { complete }
        suite.expect(complete && !events.contains { $0.type == .leftMouseDown || $0.type == .leftMouseDragged },
                     "source revalidation after pointer settling prevents pressing a stale neighbor")
    }

    private static func nativeReorderGeometry(_ suite: TestSuite) {
        let claude = CGRect(x: 1480, y: 7, width: 42, height: 26)
        let text = CGRect(x: 1526, y: 7, width: 46, height: 24)
        let docker = CGRect(x: 1435, y: 7, width: 47, height: 24)
        let all = [docker, claude, text]
        suite.expect(MenuBarMoveGeometry.isBefore(docker, claude, among: all),
                     "an adjacent icon counts as before even when frames overlap by a few points")
        suite.expect(!MenuBarMoveGeometry.isBefore(claude, docker, among: all), "an icon to the right is not before")
        suite.expect(!MenuBarMoveGeometry.isBefore(docker, text, among: all), "an icon with another between is not before")
        let rightward = MenuBarMoveGeometry.dropX(source: docker, target: text, attempt: 0)
        suite.expect(rightward < text.minX && rightward > text.minX - docker.width,
                     "a rightward drop allows for the target sliding left into the vacated slot")
        let leftward = MenuBarMoveGeometry.dropX(source: text, target: docker, attempt: 0)
        suite.expect(leftward > docker.minX && leftward < docker.midX, "a leftward drop lands on the target's leading half")
        suite.expect(MenuBarMoveGeometry.dropX(source: text, target: docker, attempt: 2) < leftward,
                     "retries move the release toward the target's leading edge")
        let row = MenuBarMoveGeometry.dragRow(docker, text)
        let start = MenuBarMoveGeometry.pressPoint(in: docker)
        suite.expect(MenuBarMoveGeometry.dragRegion(from: start, to: CGPoint(x: rightward, y: start.y), regions: [row]) != nil,
                     "the drag row contains both the press and the release")
    }
}

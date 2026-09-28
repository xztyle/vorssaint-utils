// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Command-drag transport adapted from Vorssaint PR #360 (ruvelro).
import AppKit
import CoreGraphics

enum MenuBarItemMoveError: Error {
    case permissionMissing, itemUnavailable, itemNotMovable, provisionalIdentity
    case menuOpen, eventCreationFailed, verificationFailed, busy
}

@MainActor
final class MenuBarItemMover {
    private(set) var isMoving = false

    func move(item: ManagedMenuBarItem, destinationFrame: CGRect, placeAfter: Bool) async throws {
        try check(item)
        guard item.isMovable, !item.isProtected else { throw MenuBarItemMoveError.itemNotMovable }
        isMoving = true
        defer { isMoving = false }
        try await waitForIdleInput()
        try checkFrame(item)
        let pointer = CGEvent(source: nil)?.location ?? item.frame.origin
        let displays = Self.activeDisplays()
        displays.forEach { _ = CGDisplayHideCursor($0) }
        CGAssociateMouseAndMouseCursorPosition(0)
        defer {
            CGWarpMouseCursorPosition(pointer)
            CGAssociateMouseAndMouseCursorPosition(1)
            displays.forEach { _ = CGDisplayShowCursor($0) }
        }
        let end = CGPoint(x: placeAfter ? destinationFrame.maxX + 2 : destinationFrame.minX - 2,
                          y: destinationFrame.midY)
        try await postCommandDrag(item: item, to: end)
    }

    func click(item: ManagedMenuBarItem) async throws {
        try check(item)
        isMoving = true
        defer { isMoving = false }
        try await waitForIdleInput()
        try checkFrame(item)
        let point = CGPoint(x: item.frame.midX, y: item.frame.midY)
        let source = try source()
        let down = try event(.leftMouseDown, source: source, point: point, item: item)
        let up = try event(.leftMouseUp, source: source, point: point, item: item)
        let relay = MenuBarItemEventRelay(pid: targetPID(item))
        try relay.start()
        defer { relay.close() }
        let release = try releaseGuard(up, pid: targetPID(item))
        defer { release.releaseIfArmed() }
        try await relay.send(down, press: release)
        try await Task.sleep(for: .milliseconds(35))
        try await relay.send(up, press: release)
        release.confirmRelease()
    }

    private func check(_ item: ManagedMenuBarItem) throws {
        guard AppFeature.menuBarOrganizer.isSupportedOnCurrentSystem,
              AXIsProcessTrusted() else { throw MenuBarItemMoveError.permissionMissing }
        guard item.identityState == .stable else { throw MenuBarItemMoveError.provisionalIdentity }
        guard !isMoving else { throw MenuBarItemMoveError.busy }
        guard !Self.hasAnyOpenMenu else { throw MenuBarItemMoveError.menuOpen }
    }

    private func checkFrame(_ item: ManagedMenuBarItem) throws {
        if let source = item.sourcePID {
            guard let app = NSRunningApplication(processIdentifier: source), !app.isTerminated,
                  app.bundleIdentifier == item.bundleIdentifier else { throw MenuBarItemMoveError.itemUnavailable }
        }
        guard let frame = MenuBarWindowServerBridge.shared.frame(for: item.windowID),
              MenuBarOrganizerSupport.frameMatchScore(frame, item.frame) != nil,
              NSRunningApplication(processIdentifier: item.ownerPID)?.isTerminated == false
        else { throw MenuBarItemMoveError.itemUnavailable }
    }

    private func targetPID(_ item: ManagedMenuBarItem) -> pid_t {
        MenuBarOrganizerSupport.eventTargetPID(ownerPID: item.ownerPID,
            ownerBundleIdentifier: item.ownerBundleIdentifier, sourcePID: item.sourcePID)
    }

    private func waitForIdleInput() async throws {
        for _ in 0..<30 {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            let button = CGEventSource.buttonState(.combinedSessionState, button: .left)
                || CGEventSource.buttonState(.combinedSessionState, button: .right)
            if !button, flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty {
                try Task.checkCancellation()
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw MenuBarItemMoveError.busy
    }

    private func source() throws -> CGEventSource {
        guard let source = MenuBarItemEventFactory.source() else { throw MenuBarItemMoveError.eventCreationFailed }
        return source
    }

    private func event(_ type: CGEventType, source: CGEventSource, point: CGPoint,
                       item: ManagedMenuBarItem, moving: Bool = false) throws -> CGEvent {
        guard let event = MenuBarItemEventFactory.make(type, source: source, point: point,
            windowID: item.windowID, targetPID: targetPID(item), moving: moving)
        else { throw MenuBarItemMoveError.eventCreationFailed }
        return event
    }

    private func postCommandDrag(item: ManagedMenuBarItem, to end: CGPoint) async throws {
        let start = CGPoint(x: item.frame.midX, y: item.frame.midY)
        let targetPID = targetPID(item)
        let source = try source()
        let down = try event(.leftMouseDown, source: source, point: start, item: item, moving: true)
        let up = try event(.leftMouseUp, source: source, point: end, item: item, moving: true)
        let relay = MenuBarItemEventRelay(pid: targetPID)
        try relay.start()
        defer { relay.close() }
        let release = try releaseGuard(up, pid: targetPID)
        defer { release.releaseIfArmed() }
        CGWarpMouseCursorPosition(start)
        try await relay.send(down, press: release)
        try await Task.sleep(for: .milliseconds(18))
        try await postDragSteps(item: item, source: source, from: start, to: end, relay: relay, press: release)
        try await relay.send(up, press: release)
        release.confirmRelease()
    }

    private func postDragSteps(item: ManagedMenuBarItem, source: CGEventSource, from start: CGPoint,
                               to end: CGPoint, relay: MenuBarItemEventRelay, press: MenuBarPressReleaseGuard) async throws {
        for step in 1...10 {
            let fraction = CGFloat(step) / 10
            let point = CGPoint(x: start.x + (end.x - start.x) * fraction,
                                y: start.y + (end.y - start.y) * fraction)
            try await relay.send(event(.leftMouseDragged, source: source, point: point, item: item, moving: true), press: press)
            try await Task.sleep(for: .milliseconds(8))
        }
    }

    private func releaseGuard(_ up: CGEvent, pid: pid_t) throws -> MenuBarPressReleaseGuard {
        guard let releaseEvent = up.copy() else { throw MenuBarItemMoveError.eventCreationFailed }
        let guardItem = MenuBarPressReleaseGuard {
            releaseEvent.post(tap: .cgSessionEventTap)
            releaseEvent.postToPid(pid)
        }
        guardItem.schedule()
        return guardItem
    }

    static var hasAnyOpenMenu: Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]] else { return true }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let popup = Int(CGWindowLevelForKey(.popUpMenuWindow))
        return windows.contains { entry in
            guard let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  pid != ownPID,
                  let level = (entry[kCGWindowLayer as String] as? NSNumber)?.intValue else { return false }
            return level == popup
        }
    }

    private static func activeDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return [] }
        return Array(displays.prefix(Int(count)))
    }
}

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
        guard MenuBarMoveGeometry.isOnMenuRow(destinationFrame, screens: Self.screenFrames()),
              abs(destinationFrame.minY - item.frame.minY) <= 1 else { throw MenuBarItemMoveError.itemUnavailable }
        try await dragWithCursor(item, to: MenuBarMoveGeometry.point(in: destinationFrame, after: placeAfter))
    }

    private func dragWithCursor(_ item: ManagedMenuBarItem, to end: CGPoint) async throws {
        let pointer = mouseLocation(item)
        let displays = Self.activeDisplays()
        var restorePointer = false
        displays.forEach { _ = CGDisplayHideCursor($0) }
        CGAssociateMouseAndMouseCursorPosition(0)
        defer {
            if restorePointer { CGWarpMouseCursorPosition(pointer) }
            CGAssociateMouseAndMouseCursorPosition(1)
            displays.forEach { _ = CGDisplayShowCursor($0) }
        }
        do {
            try await postCommandDrag(item: item, to: end)
            restorePointer = await waitForRestingFrame(item)
            if !restorePointer { throw MenuBarItemMoveError.verificationFailed }
        } catch {
            restorePointer = await recoverRelease(item, at: end)
            throw error
        }
    }

    private func mouseLocation(_ item: ManagedMenuBarItem) -> CGPoint {
        CGEvent(source: nil)?.location ?? item.frame.origin
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
              MenuBarMoveGeometry.isOnMenuRow(frame, screens: Self.screenFrames()),
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
        let start = CGPoint(x: item.frame.midX, y: item.frame.minY)
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

    private func recoverRelease(_ item: ManagedMenuBarItem, at point: CGPoint) async -> Bool {
        // Unstructured cleanup is not cancelled with the interrupted gesture.
        await Task { @MainActor in
            let relay = MenuBarItemEventRelay(pid: targetPID(item))
            defer { relay.close() }
            do {
                let up = try event(.leftMouseUp, source: source(), point: point, item: item, moving: true)
                let release = try releaseGuard(up, pid: targetPID(item))
                defer { release.releaseIfArmed() }
                try relay.start()
                try await relay.send(up, press: release)
                release.confirmRelease()
                return await waitForRestingFrame(item)
            } catch { return false }
        }.value
    }

    private func waitForRestingFrame(_ item: ManagedMenuBarItem) async -> Bool {
        var previous: CGRect?
        for _ in 0..<20 {
            do { try await Task.sleep(for: .milliseconds(20)) } catch { return false }
            if let frame = MenuBarWindowServerBridge.shared.frame(for: item.windowID) {
                if MenuBarMoveGeometry.hasSettled(frame, previous: previous, rowY: item.frame.minY) { return true }
                previous = frame
            }
        }
        return false
    }

    private static func screenFrames() -> [CGRect] {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        return NSScreen.screens.map { CGRect(x: $0.frame.minX, y: top - $0.frame.maxY,
            width: $0.frame.width, height: $0.frame.height) }
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

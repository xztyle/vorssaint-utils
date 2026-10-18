// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Visible Command-drag sequencing informed by SaneBar (SaneApps, MIT),
// AccessibilityMenuBarDragService.swift, revision 2311b2379018dd67e4134866b1ce4d599227d457.
import CoreGraphics
import Foundation
import os

@MainActor
final class MenuBarVisibleDragTransport {
    private let postEvent: (CGEvent) -> Void
    private let logger = Logger(subsystem: "io.github.xztyle.Aster", category: "MenuBarMove")

    init(postEvent: @escaping (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) }) {
        self.postEvent = postEvent
    }

    func drag(from start: CGPoint, region: CGRect, validateSource: () throws -> Void,
              destination: () throws -> CGPoint) async throws {
        let end = try destination()
        logger.notice("Visible drag: start \(start.x),\(start.y), end \(end.x),\(end.y)")
        guard MenuBarMoveGeometry.dragRegion(from: start, to: end, regions: [region]) != nil else {
            throw MenuBarItemMoveError.itemUnavailable
        }
        let release = try releaseGuard(at: start)
        release.schedule()
        defer { release.releaseIfArmed() }
        try send(.mouseMoved, at: start, press: release)
        try await Task.sleep(for: .milliseconds(60))
        try validateSource()
        _ = try destination()
        try sendCommandChange(down: true, press: release)
        try send(.leftMouseDown, at: start, press: release)
        logger.notice("Visible drag pressed")
        try await Task.sleep(for: .milliseconds(80))
        try await dragSteps(from: start, to: end, press: release)
        try await finishDrag(from: start, region: region, destination: destination, press: release)
        try sendCommandChange(down: false, press: release)
        release.confirmRelease()
        logger.notice("Visible drag released")
        try await Task.sleep(for: .milliseconds(140))
    }

    private func releaseGuard(at point: CGPoint) throws -> MenuBarPressReleaseGuard {
        let mouse = try event(.leftMouseUp, at: point, command: false)
        let command = try commandEvent(down: false)
        return MenuBarPressReleaseGuard { [postEvent] in
            postEvent(mouse)
            postEvent(command)
        }
    }

    private func commandEvent(down: Bool) throws -> CGEvent {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 55, keyDown: down) else {
            throw MenuBarItemMoveError.eventCreationFailed
        }
        event.type = .flagsChanged
        event.flags = CGEventSource.flagsState(.hidSystemState).subtracting(.maskCommand)
        if down { event.flags.insert(.maskCommand) }
        return event
    }

    private func sendCommandChange(down: Bool, press: MenuBarPressReleaseGuard) throws {
        try Task.checkCancellation()
        let event = try commandEvent(down: down)
        guard press.performIfArmed({ postEvent(event) }) else { throw MenuBarItemMoveError.verificationFailed }
    }

    private func finishDrag(from start: CGPoint, region: CGRect, destination: () throws -> CGPoint,
                            press: MenuBarPressReleaseGuard) async throws {
        let final = try destination()
        guard region.contains(final), abs(final.y - start.y) <= 1 else { throw MenuBarItemMoveError.itemUnavailable }
        try send(.leftMouseDragged, at: final, press: press)
        try await Task.sleep(for: .milliseconds(40))
        let command = CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand)
        logger.notice("Visible release: x \(final.x), y \(final.y), Command \(command)")
        try send(.leftMouseUp, at: final, press: press)
    }

    private func dragSteps(from start: CGPoint, to end: CGPoint, press: MenuBarPressReleaseGuard) async throws {
        let count = min(14, max(10, Int(ceil(abs(end.x - start.x) / 22))))
        for index in 1...count {
            let point = CGPoint(x: start.x + (end.x - start.x) * CGFloat(index) / CGFloat(count), y: start.y)
            try send(.leftMouseDragged, at: point, press: press)
            try await Task.sleep(for: .milliseconds(15))
        }
    }

    private func send(_ type: CGEventType, at point: CGPoint, press: MenuBarPressReleaseGuard) throws {
        try Task.checkCancellation()
        let event = try event(type, at: point, command: type != .mouseMoved)
        guard press.performIfArmed({ postEvent(event) }) else { throw MenuBarItemMoveError.verificationFailed }
    }

    private func event(_ type: CGEventType, at point: CGPoint, command: Bool) throws -> CGEvent {
        guard point.x.isFinite, point.y.isFinite,
              let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
        else { throw MenuBarItemMoveError.eventCreationFailed }
        event.flags = command ? .maskCommand : []
        return event
    }
}

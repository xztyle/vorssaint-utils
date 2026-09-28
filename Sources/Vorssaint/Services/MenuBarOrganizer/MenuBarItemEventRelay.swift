// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Bounded delivery handshake adapted from Ice (Jordan Baird, 2023–2025)
// and Thaw (Toni Förster, 2026), GPLv3, MenuBarItemManager+EventHelpers.swift.
import AppKit
import os

@MainActor
final class MenuBarItemEventRelay {
    private let pid: pid_t
    private var taps: [(CFMachPort, CFRunLoopSource)] = []
    private var delivery: MenuBarEventDeliveryState?
    private var mouse: CGEvent?
    private var exitEvent: CGEvent?
    private var press: MenuBarPressReleaseGuard?
    private var continuation: CheckedContinuation<Void, Error>?
    private var deadline: Task<Void, Never>?
    private let logger = Logger(subsystem: "io.github.xztyle.Aster", category: "MenuBarMove")

    init(pid: pid_t) { self.pid = pid }

    func start() throws {
        let mask = [CGEventType.null, .leftMouseDown, .leftMouseDragged, .leftMouseUp]
            .reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let target = CGEvent.tapCreateForPid(pid: pid, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: Self.targetCallback, userInfo: context)
        else { throw MenuBarItemMoveError.eventCreationFailed }
        install(target)
        guard let session = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: Self.sessionCallback, userInfo: context)
        else { close(); throw MenuBarItemMoveError.eventCreationFailed }
        install(session)
    }

    private func install(_ tap: CFMachPort) {
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)!
        taps.append((tap, source))
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func close() {
        finish(.failure(CancellationError()))
        for (tap, source) in taps {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFMachPortInvalidate(tap)
        }
        taps = []
    }

    func send(_ event: CGEvent, press: MenuBarPressReleaseGuard) async throws {
        try Task.checkCancellation()
        guard press.isArmed else { throw MenuBarItemMoveError.verificationFailed }
        guard continuation == nil, taps.count == 2, let entry = CGEvent(source: nil),
              let exit = CGEvent(source: nil) else { throw MenuBarItemMoveError.eventCreationFailed }
        let tokens = (Int64.random(in: 1...Int64.max - 2))
        entry.type = .null; exit.type = .null
        entry.setIntegerValueField(.eventSourceUserData, value: tokens)
        event.setIntegerValueField(.eventSourceUserData, value: tokens + 1)
        exit.setIntegerValueField(.eventSourceUserData, value: tokens + 2)
        delivery = MenuBarEventDeliveryState(entryToken: tokens, mouseToken: tokens + 1, exitToken: tokens + 2)
        mouse = event; exitEvent = exit; self.press = press
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                armDeadline()
                entry.postToPid(pid)
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(.failure(CancellationError())) }
        }
        guard press.isArmed else { throw MenuBarItemMoveError.verificationFailed }
    }

    private func armDeadline() {
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            self?.fail("timeout")
        }
    }

    private func fail(_ reason: String) {
        let phase = delivery?.phase.rawValue ?? "none"
        let window = mouse?.getIntegerValueField(.mouseEventWindowUnderMousePointer) ?? 0
        logger.error("Menu delivery failed: \(reason, privacy: .public), phase \(phase, privacy: .public), window \(window), host \(self.pid)")
        finish(.failure(MenuBarItemMoveError.verificationFailed))
    }

    private func finish(_ result: Result<Void, Error>) {
        deadline?.cancel(); deadline = nil
        let waiting = continuation
        continuation = nil
        if waiting != nil, case .success = result, let mouse, mouse.type != .leftMouseDragged {
            let window = mouse.getIntegerValueField(.mouseEventWindowUnderMousePointer)
            logger.notice("Menu delivery acknowledged: type \(mouse.type.rawValue), window \(window), host \(self.pid)")
        }
        waiting?.resume(with: result)
    }

    private func receive(_ type: CGEventType, _ event: CGEvent, session: Bool) -> Unmanaged<CGEvent>? {
        let unchanged = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            fail("tap disabled"); return unchanged
        }
        guard let mouse else { return unchanged }
        let token = event.getIntegerValueField(.eventSourceUserData)
        if token == delivery?.mouseToken, press?.isArmed == false {
            fail("press released"); return nil
        }
        guard continuation != nil else { return unchanged }
        let matches = matchesWindow(event, expected: mouse)
        switch delivery?.receive(token: token, isSession: session, matchesWindow: matches) {
        case .sendToSession: postWhilePressed { mouse.post(tap: .cgSessionEventTap) }; return nil
        case .sendToTarget: return postWhilePressed { mouse.postToPid(pid) } ? unchanged : nil
        case .sendExit: exitEvent?.postToPid(pid); return unchanged
        case .finish: finish(.success(())); return nil
        case .reject: recordMismatch(event, expected: mouse, session: session); fail("window changed"); return nil
        default: return unchanged
        }
    }

    private func recordMismatch(_ event: CGEvent, expected: CGEvent, session: Bool) {
        let fields: [CGEventField] = [.mouseEventWindowUnderMousePointer, .mouseEventWindowUnderMousePointerThatCanHandleThisEvent,
                                      MenuBarItemEventFactory.windowField]
        let wanted = fields.map { String(expected.getIntegerValueField($0)) }.joined(separator: ",")
        let received = fields.map { String(event.getIntegerValueField($0)) }.joined(separator: ",")
        logger.error("Menu event rebound: session \(session), type \(event.type.rawValue), expected \(wanted, privacy: .public), received \(received, privacy: .public), x \(event.location.x), y \(event.location.y)")
    }

    @discardableResult
    private func postWhilePressed(_ post: () -> Void) -> Bool {
        guard press?.performIfArmed(post) == true else { fail("press released"); return false }
        return true
    }

    private func matchesWindow(_ event: CGEvent, expected: CGEvent) -> Bool {
        var fields: [CGEventField] = [.mouseEventWindowUnderMousePointer, .mouseEventWindowUnderMousePointerThatCanHandleThisEvent]
        if expected.getIntegerValueField(MenuBarItemEventFactory.windowField) > 0 { fields.append(MenuBarItemEventFactory.windowField) }
        return event.type == expected.type && fields.allSatisfy { event.getIntegerValueField($0) == expected.getIntegerValueField($0) }
    }

    private static let targetCallback: CGEventTapCallBack = { _, type, event, context in
        guard let context else { return Unmanaged.passUnretained(event) }
        return MainActor.assumeIsolated {
            Unmanaged<MenuBarItemEventRelay>.fromOpaque(context).takeUnretainedValue().receive(type, event, session: false)
        }
    }

    private static let sessionCallback: CGEventTapCallBack = { _, type, event, context in
        guard let context else { return Unmanaged.passUnretained(event) }
        return MainActor.assumeIsolated {
            Unmanaged<MenuBarItemEventRelay>.fromOpaque(context).takeUnretainedValue().receive(type, event, session: true)
        }
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Window routing adapted from Ice (Jordan Baird, 2023–2025) and
// Thaw (Toni Förster, 2026), GPLv3, MenuBarItemEventTypes.swift.
import CoreGraphics

enum MenuBarItemEventFactory {
    // WindowServer's event window field is not exposed as a named SDK constant.
    static let windowField = CGEventField(rawValue: 0x33)!

    static func make(_ type: CGEventType, source: CGEventSource, point: CGPoint,
                     windowID: CGWindowID, targetPID: pid_t, moving: Bool) -> CGEvent? {
        guard windowID > 0, targetPID > 0, point.x.isFinite, point.y.isFinite,
              [.leftMouseDown, .leftMouseDragged, .leftMouseUp].contains(type),
              moving || type != .leftMouseDragged,
              let event = CGEvent(mouseEventSource: source, mouseType: type,
                  mouseCursorPosition: point, mouseButton: .left) else { return nil }
        event.flags = moving && type != .leftMouseUp ? .maskCommand : []
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(targetPID))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(windowID))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(windowID))
        if moving { event.setIntegerValueField(windowField, value: Int64(windowID)) }
        // As in Thaw, reordering retains CoreGraphics' default click state.
        // Explicit click counts belong to menu activation, not a held drag.
        if !moving { event.setIntegerValueField(.mouseEventClickState, value: type == .leftMouseUp ? 0 : 1) }
        return event
    }

    static func source() -> CGEventSource? {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return nil }
        source.localEventsSuppressionInterval = 0
        let permitted: CGEventFilterMask = [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents]
        for state: CGEventSuppressionState in [.eventSuppressionStateRemoteMouseDrag, .eventSuppressionStateSuppressionInterval] {
            source.setLocalEventsFilterDuringSuppressionState(permitted, state: state)
        }
        return source
    }

    static func moveEvents(source: CGEventSource, sourceWindowID: CGWindowID,
                           destinationWindowID: CGWindowID, targetPID: pid_t,
                           destination: CGPoint, fallback: CGPoint)
        -> (down: CGEvent, up: CGEvent, fallback: CGEvent)? {
        guard sourceWindowID != destinationWindowID,
              let down = make(.leftMouseDown, source: source, point: destination,
                windowID: sourceWindowID, targetPID: targetPID, moving: true),
              let up = make(.leftMouseUp, source: source, point: destination,
                windowID: destinationWindowID, targetPID: targetPID, moving: true),
              let release = make(.leftMouseUp, source: source, point: fallback,
                windowID: sourceWindowID, targetPID: targetPID, moving: true) else { return nil }
        // The host of the dragged item receives both phases. The release's
        // explicit window identifies its destination, as in Ice's transport.
        return (down, up, release)
    }

    static func routingMatches(_ event: CGEvent, expected: CGEvent, isSession: Bool = false,
                               verifiedSession: Bool = false, dragOriginWindow: CGWindowID? = nil) -> Bool {
        let window = expected.getIntegerValueField(windowField)
        // The session router can name the foreground app before the relay
        // sends our window-bound event to its host. Host delivery stays strict.
        guard event.type == expected.type,
              (isSession && window > 0)
                || event.getIntegerValueField(.eventTargetUnixProcessID) == expected.getIntegerValueField(.eventTargetUnixProcessID)
        else { return false }
        if window > 0 {
            guard event.getIntegerValueField(windowField) == window else {
                return releaseMatchesOrigin(event, expected: expected, isSession: isSession,
                    verifiedSession: verifiedSession, dragOriginWindow: dragOriginWindow)
            }
            // WindowServer updates hit-test fields as a held icon crosses its
            // neighbors. The explicit routing window still identifies the drag.
            if event.type == .leftMouseDragged || event.type == .leftMouseUp { return true }
            // Tahoe can also rewrite these fields at the host's press tap.
            // Accept this only after the session verified the original press,
            // with the same explicit window, host and Command-drag modifier.
            if !isSession, verifiedSession, expected.flags.contains(.maskCommand),
               event.flags.contains(.maskCommand) { return true }
        }
        return [CGEventField.mouseEventWindowUnderMousePointer, .mouseEventWindowUnderMousePointerThatCanHandleThisEvent]
            .allSatisfy { event.getIntegerValueField($0) == expected.getIntegerValueField($0) }
    }

    private static func releaseMatchesOrigin(_ event: CGEvent, expected: CGEvent, isSession: Bool,
                                             verifiedSession: Bool, dragOriginWindow: CGWindowID?) -> Bool {
        // Tahoe can retain the acknowledged press's window as the release's
        // event window while both hit-test fields identify the destination.
        guard !isSession, verifiedSession, event.type == .leftMouseUp,
              event.flags.isEmpty, expected.flags.isEmpty, event.location == expected.location,
              let origin = dragOriginWindow, origin > 0,
              Int64(origin) != expected.getIntegerValueField(windowField),
              event.getIntegerValueField(windowField) == Int64(origin) else { return false }
        return [CGEventField.mouseEventWindowUnderMousePointer, .mouseEventWindowUnderMousePointerThatCanHandleThisEvent]
            .allSatisfy { event.getIntegerValueField($0) == expected.getIntegerValueField($0) }
    }
}

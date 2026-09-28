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
        event.setIntegerValueField(.mouseEventClickState, value: type == .leftMouseUp ? 0 : 1)
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
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation

/// Only our tagged events can advance a delivery. Unrelated input is untouched.
struct MenuBarEventDeliveryState {
    enum Phase: String { case entry, session, target, exit, complete, failed }
    enum Action: Equatable { case pass, sendToSession, sendToTarget, sendExit, finish, reject }
    let entryToken: Int64
    let mouseToken: Int64
    let exitToken: Int64
    private(set) var phase = Phase.entry

    mutating func receive(token: Int64, isSession: Bool, matchesWindow: Bool) -> Action {
        if phase == .entry, !isSession, token == entryToken {
            phase = .session; return .sendToSession
        }
        if token == mouseToken, !matchesWindow {
            phase = .failed; return .reject
        }
        if phase == .session, isSession, token == mouseToken {
            phase = .target; return .sendToTarget
        }
        if phase == .target, !isSession, token == mouseToken {
            phase = .exit; return .sendExit
        }
        if phase == .exit, !isSession, token == exitToken {
            phase = .complete; return .finish
        }
        return .pass
    }
}

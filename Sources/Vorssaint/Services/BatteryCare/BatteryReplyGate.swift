// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import Foundation

/// Main-thread reply ownership. Errors, replies and deadlines consume the same
/// request so completion runs once, even if a stale XPC callback arrives later.
struct BatteryReplyGate {
    private var active: UUID?
    mutating func begin() -> UUID {
        let id = UUID()
        active = id
        return id
    }
    mutating func consume(_ id: UUID) -> Bool {
        guard active == id else { return false }
        active = nil
        return true
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
enum MenuBarItemMoveError: Error {
    case permissionMissing, itemUnavailable, itemNotMovable, provisionalIdentity
    case menuOpen, eventCreationFailed, verificationFailed, busy
}

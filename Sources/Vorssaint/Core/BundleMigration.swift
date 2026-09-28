// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

/// Aster has a separate identity and must never rename or retire upstream apps.
enum BundleMigration {
    @discardableResult
    static func run() -> Bool { false }
}

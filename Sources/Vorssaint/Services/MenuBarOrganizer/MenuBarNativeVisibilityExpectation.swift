// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import Foundation

/// Hiding legitimately shifts remaining icons. Unresolved icons have temporary
/// coordinate identities; their publisher and count must survive the reflow.
struct MenuBarNativeVisibilityExpectation {
    private let stable: Set<MenuBarItemIdentity>
    private let publisherCounts: [String: Int]

    init(_ items: [ManagedMenuBarItem]) {
        stable = Set(items.filter { $0.identityState == .stable }.map(\.id))
        publisherCounts = Dictionary(grouping: items, by: Self.publisher).mapValues(\.count)
    }

    func matches(_ items: [ManagedMenuBarItem]) -> Bool {
        let counts = Dictionary(grouping: items, by: Self.publisher).mapValues(\.count)
        return stable.isSubset(of: Set(items.map(\.id)))
            && publisherCounts.allSatisfy { counts[$0.key, default: 0] >= $0.value }
    }

    private static func publisher(_ item: ManagedMenuBarItem) -> String {
        item.bundleIdentifier + ":" + String(item.sourcePID ?? item.ownerPID)
    }
}

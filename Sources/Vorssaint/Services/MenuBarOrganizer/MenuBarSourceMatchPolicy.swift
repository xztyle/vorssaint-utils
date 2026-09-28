// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import CoreGraphics

struct MenuBarSourceCandidate {
    let windowID: CGWindowID
    let source: MenuBarItemSourceIdentity
    let score: CGFloat
    let sourceSlot: String
}

enum MenuBarSourceMatchPolicy {
    static func matches(_ candidates: [MenuBarSourceCandidate]) -> [CGWindowID: MenuBarItemSourceIdentity] {
        let valid = candidates.filter { $0.score.isFinite }
        let bestPerWindow = Dictionary(grouping: valid, by: \.windowID).values.compactMap(unambiguous)
        let bestPerSource = Dictionary(grouping: valid, by: \.sourceSlot).values.compactMap(unambiguous)
        let sourceWindows = Dictionary(uniqueKeysWithValues: bestPerSource.map { ($0.sourceSlot, $0.windowID) })
        let mutual = bestPerWindow.filter { sourceWindows[$0.sourceSlot] == $0.windowID }
        return Dictionary(uniqueKeysWithValues: mutual.map { ($0.windowID, $0.source) })
    }

    private static func unambiguous(_ values: [MenuBarSourceCandidate]) -> MenuBarSourceCandidate? {
        let ordered = values.sorted { $0.score < $1.score }
        guard let first = ordered.first, ordered.count == 1 || ordered[1].score - first.score > 0.5 else { return nil }
        return first
    }
}

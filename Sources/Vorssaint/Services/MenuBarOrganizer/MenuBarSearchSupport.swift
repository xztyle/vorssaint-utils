// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation

enum MenuBarSearchSupport {
    static func results(_ items: [ManagedMenuBarItem], query: String, searchAll: Bool,
                        includeAlwaysHidden: Bool) -> [ManagedMenuBarItem] {
        items.filter { item in
            (searchAll || item.section != .visible) && (includeAlwaysHidden || item.section != .alwaysHidden)
        }.compactMap { item -> (ManagedMenuBarItem, Int)? in
            score(query, in: "\(item.displayName) \(item.bundleIdentifier)").map { (item, $0) }
        }.sorted {
            if $0.1 != $1.1 { return $0.1 < $1.1 }
            return $0.0.displayName.localizedStandardCompare($1.0.displayName) == .orderedAscending
        }.map(\.0)
    }

    static func score(_ query: String, in text: String) -> Int? {
        let needle = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .filter { !$0.isWhitespace }
        let haystack = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        if needle.isEmpty { return 0 }
        if haystack.hasPrefix(needle) { return 0 }
        if haystack.contains(needle) { return 1 }
        var remainder = haystack[...]
        var distance = 2
        for character in needle {
            guard let index = remainder.firstIndex(of: character) else { return nil }
            distance += remainder.distance(from: remainder.startIndex, to: index)
            remainder = remainder[remainder.index(after: index)...]
        }
        return distance
    }
}

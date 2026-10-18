// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import Foundation

enum MenuBarNativeKeyPolicy {
    static func key(bundle: String, title: String, name: String, positions: [String: Double]) -> String? {
        if bundle == "com.apple.MenuBarAgent" {
            let modules = ["com.apple.menuextra.battery": "Battery", "com.apple.menuextra.wifi": "WiFi",
                "com.apple.menuextra.controlcenter": "BentoBox-0", "com.apple.menuextra.clock": "Clock"]
            return modules[title].map { "module:" + $0 }.flatMap { positions[$0] == nil ? nil : $0 }
        }
        let direct = positions.keys.filter { $0.hasPrefix("status:" + bundle + "::") }
        if direct.count == 1 { return direct.first }
        if direct.count > 1 { return exact(title, in: direct) }
        guard !name.isEmpty else { return nil }
        let named = positions.keys.filter { $0.hasPrefix("status:" + name + "::") }
        return named.count == 1 ? named.first : exact(title, in: named)
    }

    private static func exact(_ title: String, in keys: [String]) -> String? {
        guard !title.hasPrefix("@aster."), !title.hasPrefix("_NS:") else { return nil }
        let matches = keys.filter { $0.hasSuffix("::" + title) }
        return matches.count == 1 ? matches.first : nil
    }

    /// Unknown or pinned items divide the bar into independently movable groups.
    static func move(source: String, before target: String?, current: [String?], pinned: Set<String>,
                     positions: [String: Double]) -> [String: Double]? {
        guard let index = current.firstIndex(of: source), !pinned.contains(source) else { return nil }
        let known = current.compactMap { $0 }
        guard Set(known).count == known.count else { return nil }
        guard source != target else { return [:] }
        var start = index, end = index + 1
        while start > 0, let key = current[start - 1], !pinned.contains(key) { start -= 1 }
        while end < current.count, let key = current[end], !pinned.contains(key) { end += 1 }
        let group = current[start..<end].compactMap { $0 }
        guard target == nil || group.contains(target!) || end < current.count && target == current[end] else { return nil }
        var desired = group.filter { $0 != source }
        let destination = target.flatMap { desired.firstIndex(of: $0) } ?? desired.count
        desired.insert(source, at: destination)
        return group.count == 1 ? [:] : MenuBarNativePositionPolicy.changes(current: group, desired: desired, positions: positions)
    }
}

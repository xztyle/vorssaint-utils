// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation

struct MenuBarLayoutEntry: Codable, Equatable {
    let identity: MenuBarItemIdentity
    var section: MenuBarOrganizerSection
}

struct MenuBarLayout: Codable, Equatable {
    var entries: [MenuBarLayoutEntry] = []

    static func capture(_ items: [ManagedMenuBarItem], original: Bool = false) -> Self {
        let unique = Dictionary(grouping: items, by: \.id)
        return Self(entries: items.sorted { $0.frame.minX < $1.frame.minX }.compactMap {
            guard $0.identityState == .stable, unique[$0.id]?.count == 1 else { return nil }
            return MenuBarLayoutEntry(identity: $0.id, section: original ? .visible : $0.section)
        })
    }

    func preservingAbsent(from previous: Self, present: Set<MenuBarItemIdentity>) -> Self {
        var result = self
        for (index, entry) in previous.entries.enumerated() where !present.contains(entry.identity) {
            result.entries.insert(entry, at: min(index, result.entries.count))
        }
        return result
    }

    func includingNewItems(from snapshot: Self) -> Self {
        var result = self
        var known = Set(entries.map(\.identity))
        for (index, entry) in snapshot.entries.enumerated() where !known.contains(entry.identity) {
            let following = snapshot.entries.dropFirst(index + 1).first { known.contains($0.identity) }
            let insertion = following.flatMap { next in result.entries.firstIndex { $0.identity == next.identity } }
                ?? result.entries.count
            result.entries.insert(entry, at: insertion)
            known.insert(entry.identity)
        }
        return result
    }

    func withRevealed(_ identity: MenuBarItemIdentity) -> Self {
        var result = self
        result.entries = entries.filter { $0.identity != identity }
        result.entries.append(MenuBarLayoutEntry(identity: identity, section: .visible))
        return result
    }

    var isValid: Bool {
        entries.count <= 500 && Set(entries.map(\.identity)).count == entries.count
            && entries.allSatisfy { $0.identity.isPortable }
    }
}

extension MenuBarItemIdentity {
    var isPortable: Bool {
        !bundleIdentifier.isEmpty && !bundleIdentifier.hasPrefix("pid:")
            && !title.isEmpty && !title.hasPrefix("window:") && occurrence == 0
    }
}

struct MenuBarProfile: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var layout: MenuBarLayout
}

enum MenuBarRuleCondition: String, CaseIterable, Codable {
    case frontmostApp, onBattery, onPower, batteryBelow, timeRange, displayCount, itemPresent
}

enum MenuBarRuleAction: String, CaseIterable, Codable {
    case revealHidden, revealItem, applyProfile
}

struct MenuBarRevealRule: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var enabled = true
    var priority = 0
    var condition: MenuBarRuleCondition = .frontmostApp
    var value = ""
    var endMinute = 1080
    var action: MenuBarRuleAction = .revealHidden
    var item: MenuBarItemIdentity?
    var profileID: UUID?
    var duration: TimeInterval = 15

    var isValid: Bool {
        (1...120).contains(name.count) && value.count <= 512
            && (1...300).contains(duration) && (-100...100).contains(priority)
            && (0...1439).contains(endMinute) && (item?.isPortable ?? true)
    }
}

struct MenuBarLibrary: Codable, Equatable {
    var version = 1
    var profiles: [MenuBarProfile] = []
    var rules: [MenuBarRevealRule] = []
    var activeProfileID: UUID?

    var isValid: Bool {
        version == 1 && profiles.count <= 100 && rules.count <= 100
            && profiles.allSatisfy { (1...120).contains($0.name.count) && $0.layout.isValid }
            && rules.allSatisfy(\.isValid)
            && Set(profiles.map(\.id)).count == profiles.count
            && Set(rules.map(\.id)).count == rules.count
    }
}

struct MenuBarRuleFacts {
    let frontmostBundleID: String?
    let onBattery: Bool?
    let batteryPercent: Int?
    let minuteOfDay: Int
    let displayCount: Int
    let items: Set<MenuBarItemIdentity>
}

enum MenuBarRulePolicy {
    static func matches(_ rule: MenuBarRevealRule, facts: MenuBarRuleFacts) -> Bool {
        guard rule.enabled, rule.isValid else { return false }
        switch rule.condition {
        case .frontmostApp: return !rule.value.isEmpty && facts.frontmostBundleID == rule.value
        case .onBattery: return facts.onBattery == true
        case .onPower: return facts.onBattery == false
        case .batteryBelow: return facts.batteryPercent.map { $0 < (Int(rule.value) ?? -1) } ?? false
        case .displayCount: return facts.displayCount == Int(rule.value)
        case .itemPresent: return rule.item.map { facts.items.contains($0) } ?? false
        case .timeRange:
            guard let start = Int(rule.value), (0...1439).contains(start) else { return false }
            return start <= rule.endMinute
                ? (start..<rule.endMinute).contains(facts.minuteOfDay)
                : facts.minuteOfDay >= start || facts.minuteOfDay < rule.endMinute
        }
    }

    static func shouldEnd(_ active: MenuBarRevealRule, expires: Date?, now: Date,
                          current: MenuBarRevealRule?, facts: MenuBarRuleFacts) -> Bool {
        now >= (expires ?? .distantPast) || current != active || !matches(active, facts: facts)
    }

    static func winner(_ rules: [MenuBarRevealRule], facts: MenuBarRuleFacts,
                       consumed: Set<UUID>) -> MenuBarRevealRule? {
        rules.filter { !consumed.contains($0.id) && matches($0, facts: facts) }.sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.id.uuidString < $1.id.uuidString
        }.first
    }
}

struct MenuBarMovePlanStep: Equatable {
    let identity: MenuBarItemIdentity
    let before: MenuBarItemIdentity?
    let section: MenuBarOrganizerSection
}

enum MenuBarLayoutPolicy {
    static func plan(_ layout: MenuBarLayout, items: [ManagedMenuBarItem]) -> [MenuBarMovePlanStep] {
        let live = Dictionary(grouping: items, by: \.id)
        return MenuBarOrganizerSection.allCases.flatMap { section in
            let wanted = layout.entries.filter {
                $0.section == section && live[$0.identity]?.count == 1
                    && live[$0.identity]?.first?.identityState == .stable
            }
            return wanted.enumerated().reversed().compactMap { index, entry -> MenuBarMovePlanStep? in
                guard live[entry.identity]?.first?.isMovable == true else { return nil }
                return MenuBarMovePlanStep(identity: entry.identity,
                    before: index + 1 < wanted.count ? wanted[index + 1].identity : nil,
                    section: section)
            }
        }
    }

    static func isSatisfied(_ layout: MenuBarLayout, items: [ManagedMenuBarItem]) -> Bool {
        let live = Dictionary(grouping: items, by: \.id)
        return MenuBarOrganizerSection.allCases.allSatisfy { section in
            let wanted = layout.entries.filter {
                $0.section == section && live[$0.identity]?.count == 1
                    && live[$0.identity]?.first?.identityState == .stable
            }.map(\.identity)
            let relevant = Set(wanted)
            let actual = MenuBarOrganizerSupport.orderedItems(items, in: section)
                .filter { relevant.contains($0.id) }.map(\.id)
            return actual == wanted
        }
    }
}

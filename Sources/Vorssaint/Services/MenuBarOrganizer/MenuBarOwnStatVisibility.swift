// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import Foundation

/// How the organizer hides Aster's own stat icons on macOS 27. The system
/// hiding pass works per app and must always allow Aster, so Aster does it:
/// a Hidden stat is switched off in the bar until ‹ reveals it, and an
/// Always Hidden stat is switched off in Aster's own stat settings.
/// Values are the items' accessibility identifiers ("AsterMetric.cpu").
@MainActor
final class MenuBarOwnStatVisibility {
    static let shared = MenuBarOwnStatVisibility()
    /// Autosave and accessibility name stem of each stat item ("AsterMetric.cpu").
    nonisolated static let metricAutosavePrefix = "AsterMetric"
    nonisolated static let prefix = metricAutosavePrefix + "."
    static let didChange = Notification.Name("AsterOwnStatVisibilityDidChange")
    /// Stat item name → the stat settings the organizer switched off for it.
    static let switchedOffKey = "menuBarOrganizerSwitchedOffStats"

    private(set) var hidden: Set<String> = []
    /// Stat item name → the settings switches of the stats it draws,
    /// as of the last bar refresh.
    var statSwitches: [String: [String]] = [:]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func setHidden(_ identifiers: Set<String>) {
        guard identifiers != hidden else { return }
        hidden = identifiers
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    var switchedOff: [String: [String]] {
        defaults.dictionary(forKey: Self.switchedOffKey) as? [String: [String]] ?? [:]
    }

    /// Switches the stat off in Aster's settings and remembers what to restore.
    func switchOff(_ identifier: String) {
        guard switchedOff[identifier] == nil else { return }
        let keys = (statSwitches[identifier] ?? []).filter { defaults.bool(forKey: $0) }
        guard !keys.isEmpty else { return }
        var record = switchedOff
        record[identifier] = keys
        defaults.set(record, forKey: Self.switchedOffKey)
        keys.forEach { defaults.set(false, forKey: $0) }
    }

    /// Switches back on exactly the stat settings `switchOff` turned off.
    func switchOn(_ identifier: String) {
        forget(identifier)?.forEach { defaults.set(true, forKey: $0) }
    }

    /// Drops the record of a stat the user switched on again in Aster's
    /// settings; the organizer then lists it as visible.
    func forgetIfSwitchedBackOn(_ identifier: String) -> Bool {
        guard let keys = switchedOff[identifier], keys.contains(where: defaults.bool(forKey:)) else { return false }
        forget(identifier)
        return true
    }

    @discardableResult
    private func forget(_ identifier: String) -> [String]? {
        var record = switchedOff
        let keys = record.removeValue(forKey: identifier)
        defaults.set(record, forKey: Self.switchedOffKey)
        return keys
    }

    nonisolated static func isOwnStat(_ item: ManagedMenuBarItem) -> Bool {
        isOwnStat(item.id)
    }

    nonisolated static func isOwnStat(_ identity: MenuBarItemIdentity) -> Bool {
        identity.bundleIdentifier == Bundle.main.bundleIdentifier && identity.title.hasPrefix(prefix)
    }
}

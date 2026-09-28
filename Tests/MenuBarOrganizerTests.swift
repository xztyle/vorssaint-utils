// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import AppKit

enum MenuBarOrganizerTests {
    static func run(_ suite: TestSuite) {
        identities(suite)
        layouts(suite)
        newItems(suite)
        rules(suite)
        persistence(suite)
        search(suite)
        localization(suite)
    }

    static func item(_ name: String, x: CGFloat, section: MenuBarOrganizerSection = .visible,
                     movable: Bool = true, window: CGWindowID = 1) -> ManagedMenuBarItem {
        ManagedMenuBarItem(id: identity(name), windowID: window, ownerPID: 42,
            ownerBundleIdentifier: "test.app", sourcePID: 43, ownerName: "Host", sourceName: name,
            bundleIdentifier: "test.app", title: name, frame: CGRect(x: x, y: 0, width: 22, height: 24),
            section: section, identityState: .stable, isMovable: movable, isProtected: !movable, image: nil)
    }

    static func identity(_ name: String) -> MenuBarItemIdentity {
        MenuBarItemIdentity(bundleIdentifier: "test.app", title: name, occurrence: 0)
    }

    static func identities(_ suite: TestSuite) {
        let records = [1, 2].map { index in
            MenuBarOrganizerWindowRecord(windowID: UInt32(index), ownerPID: 43, ownerName: "Example",
                ownerBundleIdentifier: "test.app", title: "Same", frame: .zero, layer: 25, alpha: 1, isOnScreen: true)
        }
        let result = MenuBarOrganizerSupport.identities(for: records, sources: [:])
        suite.expect(result.values.allSatisfy { $0.state == .provisional }, "indistinguishable items cannot survive a restart safely")
        let hosted = MenuBarOrganizerWindowRecord(windowID: 3, ownerPID: 2, ownerName: "Control Center",
            ownerBundleIdentifier: "com.apple.controlcenter", title: "Item-1", frame: .zero, layer: 25, alpha: 1, isOnScreen: true)
        suite.expect(MenuBarOrganizerSupport.identities(for: [hosted], sources: [:])[3]?.state == .provisional,
                     "generic hosted window does not become a stable Control Center item")
        suite.expect(!AppFeature.isSupported(.menuBarOrganizer, onOperatingSystemMajorVersion: 27), "27 fails closed")
        suite.expect(AppFeature.isSupported(.menuBarOrganizer, onOperatingSystemMajorVersion: 26), "26 uses reviewed provider")
    }

    static func layouts(_ suite: TestSuite) {
        let items = [item("A", x: 0), item("B", x: 30, section: .hidden), item("Clock", x: 60, movable: false)]
        let original = MenuBarLayout.capture(items, original: true)
        suite.expect(original.entries.allSatisfy { $0.section == .visible }, "baseline restores all source items to reachability")
        let plan = MenuBarLayoutPolicy.plan(original, items: items)
        suite.expect(plan.count == 2 && plan.first?.before == identity("Clock"), "protected clock anchors restoration without being dragged")
        suite.expect(!MenuBarLayoutPolicy.isSatisfied(original, items: items), "incorrect membership fails full layout verification")
        let restored = [item("A", x: 0), item("B", x: 30), item("Clock", x: 60, movable: false)]
        suite.expect(MenuBarLayoutPolicy.isSatisfied(original, items: restored), "restored membership and order verify")
        let reversed = [item("A", x: 60), item("B", x: 30), item("Clock", x: 0, movable: false)]
        suite.expect(!MenuBarLayoutPolicy.isSatisfied(original, items: reversed), "protected anchor participates in verification")
        let absent = MenuBarLayout.capture([restored[0], restored[2]])
            .preservingAbsent(from: original, present: [identity("A"), identity("Clock")])
        suite.expect(absent == original, "temporarily absent app remains in saved position")
        suite.expect(original.withRevealed(identity("B")).entries.last?.identity == identity("B"), "temporary reveal puts item in reachable end")
        suite.expect(original.entries[1].identity == identity("B"), "temporary reveal leaves base layout intact")
    }

    static func newItems(_ suite: TestSuite) {
        let original = MenuBarLayout.capture([item("A", x: 0), item("B", x: 60)], original: true)
        let snapshot = MenuBarLayout.capture([item("New", x: 0, section: .hidden), item("A", x: 30),
                                              item("Middle", x: 60), item("B", x: 90)], original: true)
        let extended = original.includingNewItems(from: snapshot)
        suite.expect(extended.entries.map(\.identity) == ["New", "A", "Middle", "B"].map(identity),
                     "new apps join original recovery order beside their nearest known neighbor")
        suite.expect(extended.entries.allSatisfy { $0.section == .visible },
                     "new apps enter original recovery baseline as visible")
        suite.expect(extended.includingNewItems(from: snapshot) == extended,
                     "repeated inventory does not duplicate newly discovered apps")
    }

    static func rules(_ suite: TestSuite) {
        let facts = MenuBarRuleFacts(frontmostBundleID: "test.app", onBattery: true, batteryPercent: 20,
                                    minuteOfDay: 30, displayCount: 2, items: [identity("A")])
        var low = MenuBarRevealRule(name: "Low", condition: .onBattery)
        var high = MenuBarRevealRule(name: "High", priority: 10, condition: .displayCount, value: "2")
        suite.expect(MenuBarRulePolicy.winner([low, high], facts: facts, consumed: [])?.id == high.id, "highest matching priority wins")
        suite.expect(MenuBarRulePolicy.winner([low, high], facts: facts, consumed: [high.id])?.id == low.id, "held condition does not retrigger consumed rule")
        high.condition = .timeRange; high.value = "1380"; high.endMinute = 60
        suite.expect(MenuBarRulePolicy.matches(high, facts: facts), "time range crosses midnight")
        high.endMinute = 15
        suite.expect(!MenuBarRulePolicy.matches(high, facts: facts), "expired overnight range does not match")
        let now = Date(timeIntervalSince1970: 100)
        suite.expect(MenuBarRulePolicy.shouldEnd(low, expires: now, now: now, current: low, facts: facts),
                     "temporary rule expires at exact deadline")
        suite.expect(!MenuBarRulePolicy.shouldEnd(low, expires: now.addingTimeInterval(1), now: now, current: low, facts: facts),
                     "matching temporary rule survives before deadline")
        suite.expect(MenuBarRulePolicy.shouldEnd(low, expires: now.addingTimeInterval(10), now: now, current: nil, facts: facts),
                     "deleting rule immediately restores base layout")
        low.duration = 301
        suite.expect(!MenuBarRulePolicy.matches(low, facts: facts), "unbounded reveal input is rejected")
        let missing = MenuBarRuleFacts(frontmostBundleID: nil, onBattery: nil, batteryPercent: nil,
                                      minuteOfDay: 0, displayCount: 1, items: [])
        suite.expect(!MenuBarRulePolicy.matches(MenuBarRevealRule(name: "Power", condition: .onPower), facts: missing),
                     "unavailable power data never means connected to power")
    }

    static func persistence(_ suite: TestSuite) {
        let domain = "test.aster.menu-bar.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = MenuBarLayoutStore(defaults: defaults)
        var library = MenuBarLibrary()
        library.profiles = [MenuBarProfile(name: "Work", layout: MenuBarLayout.capture([item("A", x: 0)]))]
        do {
            try store.save(library)
            let roundtrip = try store.library()
            suite.expect(roundtrip == library, "named profiles roundtrip without machine window IDs")
            let corrupt = Data("broken".utf8)
            defaults.set(corrupt, forKey: DefaultsKey.menuBarOrganizerLibrary)
            suite.expect((try? store.library()) == nil, "corrupt library fails explicitly")
            suite.expect(defaults.data(forKey: DefaultsKey.menuBarOrganizerLibrary) == corrupt, "corruption never silently overwrites user's library")
        } catch { suite.expect(false, "profile roundtrip: \(error)") }
        suite.expect(!SettingsBackupSupport.exportKeys().contains(DefaultsKey.menuBarOrganizerBaseline), "machine recovery baseline excluded from portable backup")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.menuBarOrganizerLibrary), "portable profile and rule intent backed up")
    }

    static func search(_ suite: TestSuite) {
        let items = [item("Music", x: 0), item("Hidden", x: 30, section: .hidden),
                     item("Secret", x: 60, section: .alwaysHidden)]
        suite.expect(MenuBarSearchSupport.results(items, query: "", searchAll: false,
                                                  includeAlwaysHidden: false).map(\.sourceName) == ["Hidden"],
                     "ordinary panel never exposes always-hidden items")
        suite.expect(MenuBarSearchSupport.results(items, query: "musc", searchAll: true,
                                                  includeAlwaysHidden: true).first?.sourceName == "Music", "fuzzy subsequence search finds item")
        suite.expect(MenuBarSearchSupport.score("cafe", in: "Café") == 0, "search ignores accents")
        suite.expect(MenuBarSearchSupport.score("zzz", in: "Music") == nil, "unrelated query stays empty")
    }

    static func localization(_ suite: TestSuite) {
        for language in AppLanguage.allCases {
            let strings = MenuBarProductStrings.localized(language)
            suite.expect(!strings.search.isEmpty && !strings.restore.isEmpty, "menu product strings exist in \(language)")
            suite.expect(!FeatureStrings.menuBarOrganizer(language).pageTitle.isEmpty, "menu base strings exist in \(language)")
            for condition in MenuBarRuleCondition.allCases {
                suite.expect(!strings.conditionName(condition).isEmpty, "rule conditions translated in \(language)")
            }
        }
    }
}

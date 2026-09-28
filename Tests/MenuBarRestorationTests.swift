// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation

enum MenuBarRestorationTests {
    static func run(_ suite: TestSuite) {
        actualUndo(suite)
        currentMacRecovery(suite)
        geometry(suite)
        permutations(suite)
    }

    static func actualUndo(_ suite: TestSuite) {
        let old = [make("ChatGPT", 0), make("Docker", 30), make("Claude", 60), make("WiFi", 90),
                   make("Control", 150, .visible, false), make("Siri", 180, .visible), make("Clock", 210, .visible, false)]
        let moved = [make("ChatGPT", 0), make("Claude", 30), make("WiFi", 60), make("Docker", 100, .hidden),
                     make("Siri", 150, .visible), make("Control", 180, .visible, false), make("Clock", 210, .visible, false)]
        let isolated = [make("ChatGPT", 0), make("Claude", 30), make("WiFi", 60), make("Docker", 100, .hidden),
                        make("Control", 150, .visible, false), make("Siri", 180, .visible), make("Clock", 210, .visible, false)]
        suite.expect(MenuBarLayoutPolicy.preservesUnmovedItems(id("Docker"), before: old, after: isolated),
                     "moving Docker alone preserves every other stable icon's section and order")
        suite.expect(!MenuBarLayoutPolicy.preservesUnmovedItems(id("Docker"), before: old, after: moved),
                     "Docker's successful move cannot hide the observed Siri and Control Center swap")
        suite.expect(!MenuBarLayoutPolicy.preservesUnmovedItems(id("Docker"), before: old,
            after: isolated.filter { $0.id != id("WiFi") }),
                     "an unrelated missing icon makes the move unsafe to acknowledge")
        let restartBaseline = [make("WiFi", 0, .visible), make("Siri", 30, .visible)]
        let changedBeforeRestart = [make("Siri", 0, .visible), make("WiFi", 30, .visible)]
        suite.expect(!MenuBarLayoutPolicy.isSatisfied(MenuBarLayout.capture(restartBaseline, original: true),
            items: changedBeforeRestart),
                     "a saved original order detects unresolved physical changes at app restart")
        let plan = MenuBarLayoutPolicy.plan(MenuBarLayout.capture(old), items: moved)
        suite.expect(plan.map(\.identity) == [id("Docker"), id("Siri")],
                     "Undo first returns Docker to its old section, then fixes the changed native order without touching Wi-Fi")
        suite.expect(plan.first?.before == id("Claude"), "Docker returns immediately before its original neighbor")
        let siri = MenuBarMovePlanStep(identity: id("Siri"), before: id("Clock"), section: .visible)
        suite.expect(!MenuBarLayoutPolicy.satisfies(siri, items: moved),
                     "being somewhere left of Clock is not proof Siri crossed Control Center")
        suite.expect(MenuBarLayoutPolicy.plan(MenuBarLayout.capture(old), items: old).isEmpty,
                     "an already restored layout generates no input at all")
        suite.expect(!MenuBarLayoutPolicy.allItemsAvailable(MenuBarLayout.capture(old), items: old.filter { $0.id != id("WiFi") }),
                     "an absent native icon keeps the Undo snapshot available for recovery")
        suite.expect(MenuBarLayoutPolicy.allItemsAvailable(MenuBarLayout.capture(old), items: old),
                     "all restored identities allow Undo to complete")
    }

    static func geometry(_ suite: TestSuite) {
        let screen = CGRect(x: 0, y: 0, width: 2056, height: 1329)
        let row = CGRect(x: 1632, y: 0, width: 38, height: 39)
        let dragging = CGRect(x: 703, y: 1229, width: 38, height: 39)
        suite.expect(MenuBarMoveGeometry.isOnMenuRow(row, screens: [screen]), "a settled icon can enter a drag")
        suite.expect(!MenuBarMoveGeometry.isOnMenuRow(dragging, screens: [screen]), "the actual failed Wi-Fi drag cannot be reused as a menu anchor")
        suite.expect(!MenuBarMoveGeometry.hasSettled(dragging, previous: dragging, rowY: 0),
                     "stable x coordinates below the menu do not authorize pointer restoration")
        suite.expect(!MenuBarMoveGeometry.hasSettled(row, previous: dragging, rowY: 0), "a single returned frame is not settled")
        suite.expect(MenuBarMoveGeometry.hasSettled(row, previous: row, rowY: 0), "two equal frames on the original row confirm settlement")
        suite.expect(MenuBarMoveGeometry.point(in: row, after: false) == CGPoint(x: 1631, y: 0),
                     "native drags stay on the menu row's top edge rather than pulling the item downward")
    }

    static func currentMacRecovery(_ suite: TestSuite) {
        let original = ["ChatGPT", "Docker", "Claude", "TextInput", "Battery", "NowPlaying",
                        "WiFi", "Control", "Siri", "Clock"]
        let current = ["Battery", "Aster", "ChatGPT", "Claude", "WiFi", "TextInput",
                       "Docker", "NowPlaying", "Siri", "Control", "Clock"]
        let protected: Set<String> = ["Control", "Clock"]
        let items = current.enumerated().map { index, name in
            make(name, CGFloat(index * 30), .visible, !protected.contains(name))
        }
        let desired = MenuBarLayout(entries: original.map {
            MenuBarLayoutEntry(identity: id($0), section: .visible)
        })
        let plan = MenuBarLayoutPolicy.plan(desired, items: items)
        suite.expect(!MenuBarLayoutPolicy.isSatisfied(desired, items: items),
                     "the current Mac order differs from its saved original layout")
        suite.expect(!plan.isEmpty && !plan.contains { protected.contains($0.identity.title) },
                     "recovery never drags protected Control Center or Clock")
        suite.expect(MenuBarLayoutPolicy.isSatisfied(desired, items: apply(plan, to: items)),
                     "planned moves restore the recorded order without moving the new Aster icon")
    }

    static func permutations(_ suite: TestSuite) {
        let desired = [make("A", 0, .visible), make("B", 30, .visible), make("C", 60, .visible), make("Clock", 90, .visible, false)]
        for order in permutationsOf(["A", "B", "C"]) {
            for hiddenMask in 0..<8 {
                var live = order.enumerated().map { make($0.element, CGFloat($0.offset * 30),
                    hiddenMask & (1 << $0.offset) == 0 ? .visible : .hidden) }
                live.append(make("Clock", 120, .visible, false))
                let layout = MenuBarLayout.capture(desired)
                let plan = MenuBarLayoutPolicy.plan(layout, items: live)
                let result = apply(plan, to: live)
                suite.expect(MenuBarLayoutPolicy.isSatisfied(layout, items: result),
                             "minimal restoration handles every three-item order and section assignment")
                suite.expect(!plan.contains { $0.identity == id("Clock") }, "protected anchors are never dragged")
            }
        }
    }

    static func apply(_ plan: [MenuBarMovePlanStep], to items: [ManagedMenuBarItem]) -> [ManagedMenuBarItem] {
        var order = Dictionary(uniqueKeysWithValues: MenuBarOrganizerSection.allCases.map {
            ($0, MenuBarOrganizerSupport.orderedItems(items, in: $0).map(\.id))
        })
        for step in plan {
            for section in MenuBarOrganizerSection.allCases { order[section]?.removeAll { $0 == step.identity } }
            let index = step.before.flatMap { order[step.section]?.firstIndex(of: $0) } ?? order[step.section, default: []].count
            order[step.section, default: []].insert(step.identity, at: index)
        }
        return MenuBarOrganizerSection.allCases.flatMap { section in
            order[section, default: []].enumerated().map { make($0.element.title, CGFloat($0.offset * 30), section, $0.element.title != "Clock") }
        }
    }

    static func permutationsOf(_ values: [String]) -> [[String]] {
        if values.isEmpty { return [[]] }
        return values.flatMap { head in permutationsOf(values.filter { $0 != head }).map { [head] + $0 } }
    }

    static func id(_ name: String) -> MenuBarItemIdentity { MenuBarOrganizerTests.identity(name) }
    static func make(_ name: String, _ x: CGFloat, _ section: MenuBarOrganizerSection = .alwaysHidden,
                     _ movable: Bool = true) -> ManagedMenuBarItem {
        MenuBarOrganizerTests.item(name, x: x, section: section, movable: movable)
    }
}

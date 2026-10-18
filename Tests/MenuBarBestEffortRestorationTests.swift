// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import AppKit

/// Executes the production recovery loop with no real menu-bar input.
enum MenuBarBestEffortRestorationTests {
    class Fixture {
        enum Failure { case unchanged, collateral, disappearance }
        var items = [make("Siri", 0, .alwaysHidden), make("WiFi", 30, .alwaysHidden),
                     make("Control", 60, .visible, false), make("Clock", 90, .visible, false)]
        var attempts: [String] = []
        var failure = Failure.unchanged
        var restoreAllowed = true
        var refreshOK = true
        func settleAndRefresh() async -> Bool { refreshOK }
        func moveItem(_ id: MenuBarItemIdentity, before: MenuBarItemIdentity?,
                      to section: MenuBarOrganizerSection, restoring: Bool) async -> Bool {
            attempts.append(id.title)
            if id.title == "Siri" {
                if failure == .collateral {
                    items = [make("WiFi", 0, .alwaysHidden), make("Siri", 30, .alwaysHidden)] + Array(items.dropFirst(2))
                }
                if failure == .disappearance { items.removeFirst() }
                return false
            }
            let step = MenuBarMovePlanStep(identity: id, before: before, section: section)
            items = MenuBarRestorationTests.apply([step], to: items)
            return true
        }
    }

    static func run(_ suite: TestSuite) {
        let continued = Host()
        suite.expect(!execute(continued, restoring: true) && continued.attempts == ["Siri", "WiFi"],
                     "unchanged failed recovery still restores independent remaining icons without claiming completion")
        suite.expect(continued.items.first(where: { $0.title == "WiFi" })?.section == .visible,
                     "the remaining successful baseline move reaches its original section")
        let normal = Host()
        suite.expect(!execute(normal, restoring: false) && normal.attempts == ["Siri"],
                     "normal profile or user moves retain fail-fast behavior")
        for failure: Fixture.Failure in [.collateral, .disappearance] {
            let unsafe = Host(); unsafe.failure = failure
            suite.expect(!execute(unsafe, restoring: true) && unsafe.attempts == ["Siri"],
                         "recovery stops on changed ordering or a missing icon")
        }
        let unavailable = Host(); unavailable.refreshOK = false
        suite.expect(!execute(unavailable, restoring: true) && unavailable.attempts == ["Siri"],
                     "an unavailable fresh inventory cannot authorize further recovery input")
        let permission = Host(); permission.restoreAllowed = false
        suite.expect(!execute(permission, restoring: true) && permission.attempts == ["Siri"],
                     "changed permissions or competing managers stop the remaining recovery input")
        topology(suite)
    }

    private static func execute(_ host: Host, restoring: Bool) -> Bool {
        let names = ["WiFi", "Control", "Siri", "Clock"]
        let layout = MenuBarLayout(entries: names.map { .init(identity: MenuBarOrganizerTests.identity($0), section: .visible) })
        var complete = false, result = true
        Task { @MainActor in result = await host.applyLayoutSteps(layout, restoring: restoring); complete = true }
        let deadline = Date().addingTimeInterval(2)
        while !complete, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.002)) }
        return complete && result
    }

    private static func topology(_ suite: TestSuite) {
        let original = [make("A", 0, .visible), make("B", 30, .visible)]
        suite.expect(MenuBarLayoutPolicy.unchangedTopology(before: original, after: original),
                     "a fresh unchanged full inventory can authorize an independent recovery step")
        let changed = [MenuBarOrganizerTests.item("A", x: 0, window: 99), make("B", 30, .visible)]
        suite.expect(!MenuBarLayoutPolicy.unchangedTopology(before: original, after: changed),
                     "a restarted icon with a replacement window is not an unchanged failed gesture")
        let crossed = [make("A", 0, .hidden), make("B", 30, .visible)]
        suite.expect(!MenuBarLayoutPolicy.unchangedTopology(before: original, after: crossed),
                     "a changed section cannot be treated as a harmless failed gesture")
        suite.expect(!MenuBarLayoutPolicy.unchangedTopology(before: [], after: []),
                     "empty inventories never authorize further input")
    }

    private static func make(_ name: String, _ x: CGFloat, _ section: MenuBarOrganizerSection,
                             _ movable: Bool = true) -> ManagedMenuBarItem {
        MenuBarOrganizerTests.item(name, x: x, section: section, movable: movable)
    }
}

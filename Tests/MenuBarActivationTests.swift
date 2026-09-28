// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import AppKit

/// Runs the production activation transaction with inert display, click and
/// movement endpoints. These tests never post input or create status items.
enum MenuBarActivationTests {
    final class Clicker {
        var clicks = 0
        func click(item: ManagedMenuBarItem) async throws { clicks += 1 }
    }
    class Fixture {
        var items = [MenuBarOrganizerTests.item("A", x: 0, section: .alwaysHidden)]
        var hiddenSectionShown = false
        var alwaysHiddenSectionShown = false
        var pendingActivationRestore: MenuBarLayout?
        var pendingActivationVisibility: (Bool, Bool)?
        var operationMessage: String?
        var entryAllowed = true
        var refreshResults = [true, true]
        var moveSucceeds = true
        var restoreSucceeds = true
        var reachable = true
        var menuCloses = true
        var applied = 0
        let mover = Clicker()
        let text = FeatureStrings.menuBarOrganizer(.enUS)
        let extra = MenuBarProductStrings.localized(.enUS)
        func settleAndRefresh() async -> Bool { refreshResults.isEmpty ? true : refreshResults.removeFirst() }
        func revealInMenuBar(_ section: MenuBarOrganizerSection) { hiddenSectionShown = true; alwaysHiddenSectionShown = true }
        func itemIsReachable(_ identity: MenuBarItemIdentity) -> Bool { reachable }
        func applyDividerState() {}
        func moveErrorMessage(_ error: Error) -> String { "failure" }
        func waitUntilMenuCloses() async -> Bool { menuCloses }
        func applyLayout(_ layout: MenuBarLayout) async -> Bool { applied += 1; return restoreSucceeds }
        func moveItem(_ id: MenuBarItemIdentity, before: MenuBarItemIdentity?, to: MenuBarOrganizerSection) async -> Bool {
            items = [MenuBarOrganizerTests.item("A", x: 200)]
            return moveSucceeds
        }
    }

    static func execute(_ host: Host) {
        var finished = false
        Task { @MainActor in await host.activateItem(MenuBarOrganizerTests.identity("A")); finished = true }
        let deadline = Date().addingTimeInterval(2)
        while !finished, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.002)) }
    }

    static func run(_ suite: TestSuite) {
        let failedRefresh = Host(); failedRefresh.refreshResults = [true, false]
        execute(failedRefresh)
        checkHidden(failedRefresh, suite, "failed refresh")
        suite.expect(failedRefresh.mover.clicks == 0, "failed refresh never clicks stale item")
        let failedMove = Host(); failedMove.reachable = false; failedMove.moveSucceeds = false
        execute(failedMove)
        checkHidden(failedMove, suite, "failed partial move")
        suite.expect(failedMove.pendingActivationRestore?.entries.first?.section == .alwaysHidden,
                     "partial move retains original membership for safe retry")
        let unreachable = Host(); unreachable.reachable = false
        execute(unreachable)
        checkHidden(unreachable, suite, "unreachable moved item")
        suite.expect(unreachable.mover.clicks == 0, "unreachable item never clicks a guessed coordinate")
        let opened = Host(); opened.menuCloses = false
        execute(opened)
        suite.expect(opened.hiddenSectionShown && opened.alwaysHiddenSectionShown
                     && opened.pendingActivationRestore != nil && opened.applied == 0,
                     "open menu owns deferred restoration without collapsing its item")
        let normal = Host(); execute(normal)
        checkHidden(normal, suite, "successful activation")
        suite.expect(normal.pendingActivationRestore == nil && normal.applied == 1 && normal.mover.clicks == 1,
                     "closed menu restores layout once then clears recovery")
    }

    static func checkHidden(_ host: Host, _ suite: TestSuite, _ context: String) {
        suite.expect(!host.hiddenSectionShown && !host.alwaysHiddenSectionShown,
                     "\(context) restores both section visibility flags")
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import AppKit

enum MenuBarNativeSectionTests {
    final class Layout {
        var calls = 0
        var fails = false
        func move(_ identity: MenuBarItemIdentity, before target: MenuBarItemIdentity?) async throws {
            calls += 1
            if fails { throw MenuBarItemMoveError.verificationFailed }
        }
    }
    final class Visibility {
        var resets = 0
        func reset() { resets += 1 }
    }
    class Fixture {
        let layout = Layout(), visibility = Visibility()
        var catalog: [MenuBarItemIdentity: ManagedMenuBarItem] = [:]
        var assignments: [MenuBarItemIdentity: MenuBarOrganizerSection] = [:]
    }

    static func run(_ suite: TestSuite) {
        var finished = false
        Task { @MainActor in
            await membership(suite); await ordering(suite); await rejection(suite); startup(suite)
            finished = true
        }
        let deadline = Date().addingTimeInterval(2)
        while !finished, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.002)) }
        suite.expect(finished, "native section checks complete with inert movement endpoints")
    }

    private static func startup(_ suite: TestSuite) {
        let host = Host(), identity = MenuBarOrganizerTests.identity("A")
        let saved = MenuBarLayout(entries: [.init(identity: identity, section: .hidden)])
        host.assignments[identity] = .hidden
        host.prepareForStartup()
        suite.expect(host.assignments.isEmpty && host.visibility.resets == 1,
            "startup checks physical baseline with every old logical assignment cleared")
        host.loadSavedMembership(saved, recovering: true)
        suite.expect(host.assignments.isEmpty, "real recovery keeps all saved hidden assignments suspended")
        host.loadSavedMembership(saved, recovering: false)
        suite.expect(host.assignments[identity] == .hidden, "healthy startup restores the saved hidden membership after baseline verification")
    }

    private static func membership(_ suite: TestSuite) async {
        let host = Host(), item = MenuBarOrganizerTests.item("A", x: 0)
        host.catalog[item.id] = item
        for section in [MenuBarOrganizerSection.hidden, .alwaysHidden, .visible] {
            do { try await host.move(item.id, before: nil, to: section) }
            catch { suite.expect(false, "section-only change failed: \(error)") }
            suite.expect(host.assignments[item.id] == section, "native section membership changes without moving the icon")
        }
        suite.expect(host.layout.calls == 0 && host.visibility.resets == 3,
            "section-only changes reveal for editing and never rewrite physical order")
    }

    private static func ordering(_ suite: TestSuite) async {
        let host = Host(), item = MenuBarOrganizerTests.item("A", x: 0)
        host.catalog[item.id] = item; host.layout.fails = true
        do { try await host.move(item.id, before: MenuBarOrganizerTests.identity("B"), to: .hidden) }
        catch {}
        suite.expect(host.layout.calls == 1 && host.assignments.isEmpty, "failed explicit reordering cannot save a successful section change")
        host.layout.fails = false
        do { try await host.move(item.id, before: MenuBarOrganizerTests.identity("B"), to: .hidden) }
        catch { suite.expect(false, "verified order failed: \(error)") }
        suite.expect(host.layout.calls == 2 && host.assignments[item.id] == .hidden, "explicit ordering still uses the verified move endpoint")
    }

    private static func rejection(_ suite: TestSuite) async {
        let host = Host(), item = MenuBarOrganizerTests.item("Protected", x: 0, movable: false)
        host.catalog[item.id] = item
        for id in [item.id, MenuBarOrganizerTests.identity("Missing")] {
            do { try await host.move(id, before: nil, to: .hidden); suite.expect(false, "unsafe membership accepted") }
            catch { suite.expect(host.assignments.isEmpty && host.visibility.resets == 0, "protected or absent items cannot change native membership") }
        }
    }
}

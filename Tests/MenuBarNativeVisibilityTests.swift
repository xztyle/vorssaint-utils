// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import AppKit

enum MenuBarNativeVisibilityTests {
    static func run(_ suite: TestSuite) {
        let stable = MenuBarOrganizerTests.item("Stable", x: 100)
        let first = unknown(1, x: 200), second = unknown(2, x: 220)
        let expectation = MenuBarNativeVisibilityExpectation([stable, first, second])
        let moved = [stable, unknown(1, x: 300), unknown(2, x: 320)]
        suite.expect(expectation.matches(moved), "ordinary native reflow preserves unidentified icons despite changed coordinates")
        suite.expect(!expectation.matches(Array(moved.dropLast())), "losing an unidentified icon still fails visibility verification")
        suite.expect(!expectation.matches(Array(moved.dropFirst())), "a missing stable icon always fails visibility verification")
        suite.expect(!expectation.matches([stable, unknown(1, x: 300, pid: 100), unknown(2, x: 320, pid: 100)]),
            "another publisher process cannot replace the original unidentified icons")
        suite.expect(expectation.matches(moved + [MenuBarOrganizerTests.item("New", x: 400)]),
            "a newly visible icon does not hide a missing original item")
        suite.expect(!expectation.matches([stable, unknown(1, x: 300), MenuBarOrganizerTests.item("New", x: 400)]),
            "a different publisher cannot replace a missing unidentified icon")
    }

    private static func unknown(_ number: Int, x: CGFloat, pid: pid_t = 99) -> ManagedMenuBarItem {
        let title = "@aster.unresolved:\(pid):\(x)"
        return ManagedMenuBarItem(id: .init(bundleIdentifier: "test.dynamic", title: title, occurrence: 0),
            windowID: UInt32(number), ownerPID: pid, ownerBundleIdentifier: "test.host", sourcePID: pid,
            ownerName: "Host", sourceName: "Dynamic", bundleIdentifier: "test.dynamic", title: title,
            frame: CGRect(x: x, y: 0, width: 20, height: 24), section: .visible,
            identityState: .provisional, isMovable: false, isProtected: false, image: nil)
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import Foundation

enum MenuBarNativeLayoutTests {
    static func run(_ suite: TestSuite) {
        for format: PropertyListSerialization.PropertyListFormat in [.binary, .xml] { document(format, suite) }
        for bad: Any in [true, Double.nan, Double.infinity, "12", 10_000_001] {
            suite.expect((try? make(["status:app::A": bad])) == nil, "invalid menu weights fail closed")
        }
        suite.expect((try? MenuBarNativeLayoutDocument(data: Data("not a plist".utf8))) == nil,
                     "corrupt menu table is never replaced")
        suite.expect((try? make([String(repeating: "x", count: 513): 1])) == nil, "unbounded preference keys are rejected")
        weights(suite)
        keys(suite)
        anchors(suite)
        for language in AppLanguage.allCases {
            let text = MenuBarNativeStrings.localized(language)
            suite.expect(!text.grant.isEmpty && text.accessInfo.contains("com.apple.MenuBar.plist"),
                         "layout access names the exact single file in every language")
        }
    }

    private static func make(_ positions: [String: Any], format: PropertyListSerialization.PropertyListFormat = .binary) throws -> MenuBarNativeLayoutDocument {
        let root: [String: Any] = [MenuBarNativeLayoutDocument.positionsKey: positions,
            "Unrelated": ["value": Data([1, 2, 3])], "NativeFlag": true]
        return try MenuBarNativeLayoutDocument(data: PropertyListSerialization.data(fromPropertyList: root, format: format, options: 0))
    }

    private static func document(_ format: PropertyListSerialization.PropertyListFormat, _ suite: TestSuite) {
        let document = try! make(["A": -100.5, "B": 0, "C": 100.5], format: format)
        let updated = try! MenuBarNativeLayoutDocument(data: document.replacing(["A": 100.5, "C": -100.5]))
        suite.expect(updated.positions == ["A": 100.5, "B": 0, "C": -100.5], "fractional native weights keep their exact values")
        suite.expect(updated.root["NativeFlag"] as? Bool == true &&
            (updated.root["Unrelated"] as? [String: Data])?["value"] == Data([1, 2, 3]), "unknown native fields survive")
        suite.expect(updated.format == format, "the native table keeps its original encoding")
        suite.expect((try? document.replacing(["Unknown": 5])) == nil, "unknown keys are never invented")
        suite.expect((try? document.replacing(["A": Double(Int.min)])) == nil, "invalid replacement cannot overflow validation")
        suite.expect((try? document.replacing(["A": .nan])) == nil, "replacement cannot introduce a nonfinite weight")
    }

    private static func weights(_ suite: TestSuite) {
        for weights: [String: Double] in [["A": -100.5, "B": 0, "C": 100.5], ["A": 100.5, "B": 0, "C": -100.5]] {
            let changes = MenuBarNativePositionPolicy.changes(current: ["A", "B", "C"], desired: ["B", "A", "C"], positions: weights)
            suite.expect(changes == ["B": weights["A"]!, "A": weights["B"]!], "both observed weight directions can reorder")
            suite.expect(MenuBarNativePositionPolicy.changes(current: ["A", "B", "C"], desired: ["A", "B", "C"], positions: weights) == [:], "satisfied order writes nothing")
        }
        for (current, desired) in [(["A", "B"], ["A", "Unknown"]), (["A", "A"], ["A", "A"]), (["A", "B", "C"], ["B", "C", "A"])] {
            suite.expect(MenuBarNativePositionPolicy.changes(current: current, desired: desired, positions: ["A": 10, "B": 20, "C": 15]) == nil,
                         "ambiguous identities or weights cannot rearrange the bar")
        }
    }

    private static func keys(_ suite: TestSuite) {
        let positions: [String: Double] = ["module:WiFi": 182.5, "status:app::Item-0": 460.5,
            "status:other::Item-0": 500.5, "status:multi::A": 400, "status:multi::B": 420]
        suite.expect(MenuBarNativeKeyPolicy.key(bundle: "com.apple.MenuBarAgent", title: "com.apple.menuextra.wifi",
            name: "MenuBarAgent", positions: positions) == "module:WiFi", "native system keys use observed module names")
        suite.expect(MenuBarNativeKeyPolicy.key(bundle: "app", title: "@aster.single-status-item", name: "App",
            positions: positions) == "status:app::Item-0", "a unique publisher key survives dynamic AX titles")
        suite.expect(MenuBarNativeKeyPolicy.key(bundle: "multi", title: "@aster.single-status-item", name: "Multi",
            positions: positions) == nil, "multiple keys cannot be guessed from one icon")
        suite.expect(MenuBarNativeKeyPolicy.key(bundle: "multi", title: "A", name: "Multi", positions: positions)
            == "status:multi::A", "stable exact identifiers resolve multiple publisher keys")
        suite.expect(MenuBarNativeKeyPolicy.move(source: "status:app::Item-0", before: "status:other::Item-0",
            current: ["status:other::Item-0", nil, "status:app::Item-0"], pinned: [], positions: positions) == nil,
            "reordering cannot cross an unresolved native icon")
        suite.expect(MenuBarNativeKeyPolicy.move(source: "module:WiFi", before: nil,
            current: ["module:WiFi"], pinned: ["module:WiFi"], positions: positions) == nil, "pinned icons never move")
        suite.expect(MenuBarNativeKeyPolicy.move(source: "status:app::Item-0", before: "status:other::Item-0",
            current: ["status:other::Item-0", "status:app::Item-0"], pinned: [], positions: positions)
            == ["status:app::Item-0": 500.5, "status:other::Item-0": 460.5], "only the intended native group exchanges weights")
    }

    private static func anchors(_ suite: TestSuite) {
        let weights: [String: Double] = ["A": 500.5, "B": 460.5, "Pin": 156.5, "C": 100.5]
        let current: [String?] = ["A", "B", "Pin", "C"]
        suite.expect(MenuBarNativeKeyPolicy.move(source: "A", before: "Pin", current: current,
            pinned: ["Pin"], positions: weights) == ["B": 500.5, "A": 460.5],
            "the adjacent right anchor permits appending within the movable group")
        suite.expect(MenuBarNativeKeyPolicy.move(source: "A", before: "C", current: current,
            pinned: ["Pin"], positions: weights) == nil, "a native move never crosses a pinned anchor")
        suite.expect(MenuBarNativeKeyPolicy.move(source: "C", before: "Pin", current: current,
            pinned: ["Pin"], positions: weights) == nil, "a target on the left side of an anchor is rejected")
        suite.expect(MenuBarNativeKeyPolicy.move(source: "A", before: "A", current: current,
            pinned: ["Pin"], positions: weights) == [:], "dropping an icon on itself changes nothing")
        suite.expect(MenuBarNativeKeyPolicy.move(source: "A", before: nil, current: ["A", "A", "B"],
            pinned: [], positions: weights) == nil, "two icons mapped to one native key cannot move")
        suite.expect(MenuBarNativePositionPolicy.changes(current: ["A", "B"], desired: ["B", "A"],
            positions: ["A": .infinity, "B": 1]) == nil, "a nonfinite pure-policy weight cannot be permuted")
    }
}

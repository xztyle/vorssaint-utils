// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import Foundation

enum MenuBarNativePreferenceTests {
    static func run(_ suite: TestSuite) {
        do {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("AsterMenuPreference-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let file = root.appendingPathComponent("menu.plist")
            let original: [String: Any] = [MenuBarNativeLayoutDocument.positionsKey: ["A": 20.5, "B": 10.5, "Unmoved": NSNumber(value: 30)],
                "Unknown": ["Flag": true, "Bytes": Data([1, 2, 3])]]
            try PropertyListSerialization.data(fromPropertyList: original, format: .binary, options: 0).write(to: file)
            let snapshot = try MenuBarNativeLayoutDocument(data: Data(contentsOf: file))
            suite.expect(MenuBarNativePreferenceStore.equal(try MenuBarNativePreferenceStore.read(at: file), original),
                "the exact file domain reads the original preference cache")
            let updated = try MenuBarNativeLayoutDocument(data: snapshot.replacing(["A": 10.5, "B": 20.5]))
            let written = try MenuBarNativePreferenceStore.write(updated, basedOn: snapshot, at: file)
            let actual = try MenuBarNativeLayoutDocument(data: written)
            suite.expect(actual.positions == updated.positions, "native preference writes publish the intended weights")
            suite.expect(MenuBarNativePreferenceStore.equal(actual.root, updated.root), "native preference writes preserve unrelated fields")
            let values = actual.root[MenuBarNativeLayoutDocument.positionsKey] as? [String: NSNumber]
            suite.expect(values?["Unmoved"].map { String(cString: $0.objCType) } == String(cString: NSNumber(value: 30).objCType),
                "native publication preserves the scalar type of an untouched accepted weight")
            suite.expect(MenuBarNativePreferenceStore.equal(try MenuBarNativePreferenceStore.read(at: file), actual.root),
                "the synchronized cache matches the actual file after publication")
            try refusal(snapshot, current: actual, file: file, suite)
        } catch { suite.expect(false, "real native preference check failed: \(error)") }
    }

    private static func refusal(_ stale: MenuBarNativeLayoutDocument, current: MenuBarNativeLayoutDocument,
                                file: URL, _ suite: TestSuite) throws {
        suite.expect((try? MenuBarNativePreferenceStore.write(stale, basedOn: stale, at: file)) == nil,
            "a stale cached layout cannot overwrite a newer change")
        var changed = current.root; changed["Unknown"] = "unauthorized change"
        let forbidden = try MenuBarNativeLayoutDocument(data: PropertyListSerialization.data(fromPropertyList: changed, format: .binary, options: 0))
        suite.expect((try? MenuBarNativePreferenceStore.write(forbidden, basedOn: current, at: file)) == nil,
            "layout publication cannot change unrelated preference fields")
        suite.expect(try Data(contentsOf: file) == current.data, "refused native writes preserve the exact existing file")
    }
}

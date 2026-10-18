// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import Foundation

enum MenuBarBookmarkTests {
    static func run(_ suite: TestSuite) {
        do {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("AsterBookmark-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let file = root.appendingPathComponent("menu.plist")
            try Data("before".utf8).write(to: file)
            var bookmark = try file.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            try Data("after".utf8).write(to: file, options: .atomic)
            let original = bookmark
            let result = try MenuBarBookmarkAccess.perform(bookmark: bookmark, expected: file, renew: { bookmark = $0 }) { try Data(contentsOf: $0) }
            suite.expect(result == Data("after".utf8), "atomic file replacement keeps the already granted layout readable")
            suite.expect(bookmark != original, "replaced-file access refreshes its existing stale bookmark")
            let next = try MenuBarBookmarkAccess.perform(bookmark: bookmark, expected: file, renew: { bookmark = $0 }) { try Data(contentsOf: $0) }
            suite.expect(next == result, "refreshed access works on a later read")
            var used = false
            suite.expect((try? MenuBarBookmarkAccess.perform(bookmark: bookmark, expected: root.appendingPathComponent("other.plist"),
                renew: { _ in }, action: { _ in used = true })) == nil && !used,
                "a resolved bookmark cannot expand access to a different file")
        } catch { suite.expect(false, "real bookmark recovery failed: \(error)") }
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Real files/index, stable capture identity, fresh immutable revision names.
enum ScreenshotHistoryRevisionTests {
    static func run(_ suite: TestSuite) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RecentCaptureStore(directoryURL: root)
        guard store.loadIfNeeded() else { suite.expect(false, "create revision history"); return }
        let id = UUID()
        let original = entry(id: id, fileID: UUID(), edited: false)
        let edited = entry(id: id, fileID: UUID(), edited: true)
        do {
            try write(original, bytes: Data([1, 2, 3]), root: root)
            store.entries = [original]
            suite.expect(store.persist(), "initial screenshot commits")
            try write(edited, bytes: Data([4, 5, 6]), root: root)
            try FileManager.default.moveItem(at: root.appendingPathComponent("history.json"),
                                            to: root.appendingPathComponent("old-index"))
            try FileManager.default.createDirectory(at: root.appendingPathComponent("history.json"),
                                                    withIntermediateDirectories: false)
            store.entries = [edited]
            suite.expect(!store.persist() && RecentCaptureStore.isRegularFile(root.appendingPathComponent(original.screenshotName!)),
                         "failed revision index write preserves prior committed pixels")
            try FileManager.default.removeItem(at: root.appendingPathComponent("history.json"))
            try FileManager.default.moveItem(at: root.appendingPathComponent("old-index"),
                                            to: root.appendingPathComponent("history.json"))
            suite.expect(store.persist(), "the new revision can commit after storage recovers")
            verifyRestart(root, id: id, edited: edited, suite: suite)
        } catch { suite.expect(false, "revision history fixture: \(error)") }
    }

    private static func verifyRestart(_ root: URL, id: UUID, edited: RecentCaptureEntry, suite: TestSuite) {
        let reopened = RecentCaptureStore(directoryURL: root)
        suite.expect(reopened.loadIfNeeded() && reopened.entries.count == 1
                     && reopened.entries[0].id == id && reopened.entries[0].edited == true,
                     "restart restores one edited capture with its original identity")
        suite.expect((try? Data(contentsOf: root.appendingPathComponent(edited.screenshotName!))) == Data([4, 5, 6]),
                     "restart resolves the committed revision rather than the original bytes")
    }

    private static func entry(id: UUID, fileID: UUID, edited: Bool) -> RecentCaptureEntry {
        var entry = RecentCaptureEntry(
            id: id, kind: .screenshot, createdAt: Date(timeIntervalSince1970: 1),
            screenshotName: "\(fileID.uuidString).png", recordingPath: nil,
            thumbnailName: "\(fileID.uuidString)-thumbnail.png", scale: 2,
            anchorX: 0, anchorY: 0, anchorWidth: 120, anchorHeight: 80)
        entry.edited = edited
        return entry
    }

    private static func write(_ entry: RecentCaptureEntry, bytes: Data, root: URL) throws {
        try RecentCaptureStore.write(bytes, to: root.appendingPathComponent(entry.screenshotName!))
        try RecentCaptureStore.write(bytes, to: root.appendingPathComponent(entry.thumbnailName!))
    }
}

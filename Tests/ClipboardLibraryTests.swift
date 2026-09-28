// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import AppKit
import SQLite3

/// Every test uses a disposable generated library. No general pasteboard,
/// installed app history, or user files are opened.
enum ClipboardLibraryTests {
    static func run(_ suite: TestSuite) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AsterClipboardTests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            try durableSearchAndBackup(suite, root: root)
            try legacyMigration(suite, root: root)
            try transactionFailure(suite, root: root)
            try representationBackup(suite, root: root)
            try largeSearch(suite, root: root)
            privacyAndRepresentations(suite)
        } catch { suite.expect(false, "clipboard fixture operation failed: \(error)") }
    }

    private static func durableSearchAndBackup(_ suite: TestSuite, root: URL) throws {
        let store = try ClipboardLibraryStore(root: root.appendingPathComponent("library"))
        var first = ClipboardHistoryEntry(text: "  Reunião com João\n", copiedAt: Date(timeIntervalSince1970: 100))
        first.title = "Quarterly plan"
        first.sourceApp = "Fixture Editor"
        let second = ClipboardHistoryEntry(text: "other copy", copiedAt: Date(timeIntervalSince1970: 50))
        let collection = ClipboardCollection(name: "Research", color: 3, entryIDs: [second.id, first.id])
        first.collectionIDs = [collection.id]
        let snapshot = ClipboardLibrarySnapshot(entries: [first, second], collections: [collection])
        try store.save(snapshot)
        suite.expect(try store.load() == snapshot, "transaction round trip preserves exact whitespace, dates and collection order")
        suite.expect(try store.search("reuniao JOAO") == [first.id], "indexed substring search ignores accents and case")
        suite.expect(try store.search("arter app:fixture type:text") == [first.id], "title substrings and metadata filters share the index")
        suite.expect(try store.search("%") == [], "literal SQL wildcard never broadens a query")
        let archive = root.appendingPathComponent("roundtrip.asterclipboard")
        try ClipboardLibraryArchive.export(store: store, snapshot: snapshot, to: archive)
        let restored = try ClipboardLibraryArchive.read(archive, staging: root.appendingPathComponent("restored"))
        suite.expect(restored == snapshot, "online backup includes the current WAL commit and restores losslessly")
        try store.save(.init(entries: [second], collections: []))
        suite.expect(try store.search("reuniao").isEmpty, "deletion removes the search row in the same transaction")
        try verifyArchiveCorruption(suite, archive: archive, root: root)
        let mode = try FileManager.default.attributesOfItem(atPath: store.databaseURL.path)[.posixPermissions] as? NSNumber
        suite.expect(mode?.intValue == 0o600, "clipboard database is owner-only")
    }

    private static func verifyArchiveCorruption(_ suite: TestSuite, archive: URL, root: URL) throws {
        let dataURL = archive.appendingPathComponent("ClipboardLibrary.sqlite")
        var data = try Data(contentsOf: dataURL)
        data.append(0)
        try data.write(to: dataURL)
        do {
            _ = try ClipboardLibraryArchive.read(archive, staging: root.appendingPathComponent("damaged"))
            suite.expect(false, "damaged archive must be rejected before replacement")
        } catch { suite.expect(true, "damaged archive rejected before replacement") }
        do {
            _ = try ClipboardLibraryArchive.safeAsset("../escape", in: root)
            suite.expect(false, "asset traversal must be rejected")
        } catch { suite.expect(true, "asset traversal rejected") }
    }

    private static func legacyMigration(_ suite: TestSuite, root: URL) throws {
        let legacy = root.appendingPathComponent("legacy")
        let destination = root.appendingPathComponent("migrated")
        PrivateFileStore.createDirectory(at: legacy, container: legacy)
        let old = ClipboardHistoryEntry(text: "legacy contents", pinnedAt: Date(timeIntervalSince1970: 123))
        let missing = ClipboardHistoryEntry(text: "", kind: .image, imageFile: "absent.png", imageHash: "fixture")
        let original = try JSONEncoder().encode([old, missing])
        try original.write(to: legacy.appendingPathComponent("ClipboardHistory.json"))
        let store = try ClipboardLibraryStore(root: destination)
        suite.expect(try ClipboardLibraryMigration.importLegacy(at: legacy, into: store) == 2, "legacy import keeps every entry including unavailable images")
        suite.expect(try ClipboardLibraryMigration.importLegacy(at: legacy, into: store) == 0, "restart cannot import the same legacy source twice")
        let loaded = try store.load()
        suite.expect(Set(loaded.entries.map(\.id)) == [old.id, missing.id], "migration preserves UUIDs")
        suite.expect(try Data(contentsOf: legacy.appendingPathComponent("ClipboardHistory.json")) == original, "migration never changes its legacy source")
        let archive = root.appendingPathComponent("missing.asterclipboard")
        try ClipboardLibraryArchive.export(store: store, snapshot: loaded, to: archive)
        suite.expect(try ClipboardLibraryArchive.inspect(archive).unavailable == ["absent.png"], "missing legacy image is explicitly recorded in backup manifest")
    }

    private static func transactionFailure(_ suite: TestSuite, root: URL) throws {
        let store = try ClipboardLibraryStore(root: root.appendingPathComponent("failure"))
        let original = ClipboardHistoryEntry(text: "acknowledged durable content")
        let snapshot = ClipboardLibrarySnapshot(entries: [original], collections: [])
        try store.save(snapshot)
        var connection: OpaquePointer?
        sqlite3_open(store.databaseURL.path, &connection)
        defer { sqlite3_close(connection) }
        sqlite3_exec(connection, "CREATE TRIGGER fail_write BEFORE INSERT ON clips BEGIN SELECT RAISE(ABORT, 'fixture simulated disk failure'); END", nil, nil, nil)
        do {
            try store.save(.init(entries: [ClipboardHistoryEntry(text: "not acknowledged")], collections: []))
            suite.expect(false, "failed insert must reject the whole snapshot")
        } catch { suite.expect(try store.load() == snapshot, "failed save rolls back earlier deletes and retains acknowledged content") }
        suite.expect(try store.search("acknowledged") == [original.id], "failed transaction retains its search index")
    }

    private static func representationBackup(_ suite: TestSuite, root: URL) throws {
        let store = try ClipboardLibraryStore(root: root.appendingPathComponent("representations"))
        let assets = store.root.appendingPathComponent("ClipboardImages")
        PrivateFileStore.createDirectory(at: assets, container: store.root)
        let bytes = Data([0, 1, 13, 255, 128, 10])
        PrivateFileStore.write(bytes, to: assets.appendingPathComponent("exact.payload"))
        var entry = ClipboardHistoryEntry(text: "rich fallback")
        entry.representations = [NSPasteboard.PasteboardType.rtf.rawValue: "exact.payload"]
        let snapshot = ClipboardLibrarySnapshot(entries: [entry], collections: [])
        try store.save(snapshot)
        let archive = root.appendingPathComponent("representations.asterclipboard")
        try ClipboardLibraryArchive.export(store: store, snapshot: snapshot, to: archive)
        suite.expect(try Data(contentsOf: archive.appendingPathComponent("ClipboardImages/exact.payload")) == bytes,
                     "backup preserves representation bytes exactly")
        var edited = entry
        edited.title = "new searchable title"
        try store.save(.init(entries: [edited], collections: []))
        suite.expect(try store.search("searchable") == [entry.id], "updating a clip reindexes its existing row")
        try store.save(snapshot)
        suite.expect(try store.search("searchable").isEmpty, "repeated update removes the previous index document")
        let data = Data("[{\"text\":\"old no uuid\",\"copiedAt\":42}]".utf8)
        suite.expect(try ClipboardLibraryMigration.importData(data, source: root, into: store, marker: "defaults-fixture.complete") == 1,
                     "UserDefaults-only legacy data uses the same verified migration path")
        suite.expect(try ClipboardLibraryMigration.importData(data, source: root, into: store, marker: "defaults-fixture.complete") == 0,
                     "UserDefaults legacy retry does not duplicate imported content")
        suite.expect(try ClipboardLibraryMigration.decodeLegacy(data) == ClipboardLibraryMigration.decodeLegacy(data),
                     "legacy records without UUIDs get deterministic identities across interrupted imports")
    }

    private static func largeSearch(_ suite: TestSuite, root: URL) throws {
        let store = try ClipboardLibraryStore(root: root.appendingPathComponent("large"))
        let entries = (0..<50_000).map { index in
            ClipboardHistoryEntry(text: "Generated fixture \(index) \(index == 43_211 ? "needle café 日本語" : "ordinary clipboard document")",
                                  copiedAt: Date(timeIntervalSince1970: Double(index)))
        }
        try store.save(.init(entries: entries, collections: []))
        var durations: [Double] = []
        for _ in 0..<20 {
            let start = Date()
            let found = try store.search("needle cafe")
            durations.append(Date().timeIntervalSince(start))
            suite.expect(found == [entries[43_211].id], "50k history returns the exact indexed match")
        }
        let p95 = durations.sorted()[18] * 1_000
        print("Clipboard fixture search: 50,000 records, p95 \(String(format: "%.2f", p95)) ms (SQL only; UI latency unmeasured)")
        suite.expect(p95 < 100, "50k indexed SQL search p95 is below 100 ms")
        suite.expect(try store.search("日本語") == [entries[43_211].id], "Unicode trigram search retains Japanese text")
        let untouched = ClipboardLibraryArchive.merge(.init(entries: [entries[0]], collections: []), into: try store.load())
        suite.expect(untouched.entries.count == 50_000, "merge is idempotent and does not lose existing entries")
    }

    private static func privacyAndRepresentations(_ suite: TestSuite) {
        suite.expect(ClipboardLibraryFocus.search.next(reverse: false) == .results
                     && ClipboardLibraryFocus.results.next(reverse: false) == .collections
                     && ClipboardLibraryFocus.search.next(reverse: true) == .collections,
                     "Tab cycles search, results and collections in both directions")
        for marker in ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType"] {
            suite.expect(ClipboardHistorySensitiveText.isConcealed([marker, "public.utf8-plain-text"]), "capture rejects \(marker) before payload reads")
        }
        suite.expect(ClipboardHistoryPasteboardText.preferredText(webURLString: nil, plainText: "  exact\n") == "  exact\n", "capture preserves text whitespace")
        for language in AppLanguage.allCases {
            let strings = ClipboardLibraryStrings(language: language)
            suite.expect(!strings.collections.isEmpty && !strings.exportLibrary.isEmpty && !strings.retentionWarning.isEmpty,
                         "clipboard library controls exist in \(language.rawValue)")
        }
    }
}

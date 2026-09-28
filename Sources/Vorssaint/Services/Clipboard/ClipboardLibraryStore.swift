// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SQLite3

struct ClipboardCollection: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var color: Int = 0
    var entryIDs: [UUID] = []
}

struct ClipboardLibrarySnapshot: Codable, Equatable {
    var entries: [ClipboardHistoryEntry]
    var collections: [ClipboardCollection]
}

enum ClipboardLibraryError: Error, LocalizedError {
    case storage(String)
    case invalidArchive
    case invalidLegacy
    var errorDescription: String? {
        switch self {
        case .storage(let message): return message
        case .invalidArchive: return "The clipboard library is incomplete or damaged. Nothing was replaced."
        case .invalidLegacy: return "The old clipboard history could not be read. Its original files are unchanged."
        }
    }
}

/// A connection is used only on its owning serial queue. Commits use FULL
/// durability; individual records and index rows change in the same transaction.
final class ClipboardLibraryStore {
    let root: URL
    let databaseURL: URL
    private var db: OpaquePointer?
    private var saved: [UUID: ClipboardHistoryEntry] = [:]
    private var savedPositions: [UUID: Int] = [:]
    private var savedCollections: [ClipboardCollection] = []
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(root: URL) throws {
        self.root = root
        databaseURL = root.appendingPathComponent("ClipboardLibrary.sqlite")
        _ = try ClipboardLibraryArchive.safeAsset(databaseURL.lastPathComponent, in: root)
        guard PrivateFileStore.createDirectory(at: root, container: root),
              sqlite3_open_v2(databaseURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK
        else { throw ClipboardLibraryError.storage("Clipboard storage could not be opened.") }
        var schema = 0
        try rows("PRAGMA user_version") { schema = Int(sqlite3_column_int($0, 0)) }
        guard schema <= 1 else { throw ClipboardLibraryError.storage("This library needs a newer version of Aster.") }
        try execute("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA secure_delete=ON; PRAGMA foreign_keys=ON;")
        try execute("CREATE TABLE IF NOT EXISTS clips(id TEXT PRIMARY KEY, position INTEGER, copied REAL, kind TEXT, source TEXT, payload BLOB); CREATE INDEX IF NOT EXISTS clips_copied ON clips(copied DESC);")
        try execute("CREATE VIRTUAL TABLE IF NOT EXISTS search USING fts5(id UNINDEXED, body, tokenize='trigram');")
        try execute("CREATE TABLE IF NOT EXISTS state(key TEXT PRIMARY KEY, payload BLOB); PRAGMA user_version=1;")
        try integrityCheck()
        tightenPermissions()
    }

    deinit { sqlite3_close(db) }

    func load() throws -> ClipboardLibrarySnapshot {
        var entries: [ClipboardHistoryEntry] = []
        var positions: [UUID: Int] = [:]
        try rows("SELECT payload,position FROM clips ORDER BY copied DESC, position") { statement in
            let entry = try JSONDecoder().decode(ClipboardHistoryEntry.self, from: blob(statement, 0))
            entries.append(entry)
            positions[entry.id] = Int(sqlite3_column_int64(statement, 1))
        }
        var collections: [ClipboardCollection] = []
        try rows("SELECT payload FROM state WHERE key='collections'") { statement in
            collections = try JSONDecoder().decode([ClipboardCollection].self, from: blob(statement, 0))
        }
        guard Set(entries.map(\.id)).count == entries.count else { throw ClipboardLibraryError.invalidArchive }
        saved = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        savedPositions = positions
        savedCollections = collections
        return ClipboardLibrarySnapshot(entries: entries, collections: collections)
    }

    func save(_ snapshot: ClipboardLibrarySnapshot) throws {
        guard Set(snapshot.entries.map(\.id)).count == snapshot.entries.count else { throw ClipboardLibraryError.invalidArchive }
        let current = Dictionary(uniqueKeysWithValues: snapshot.entries.map { ($0.id, $0) })
        let positions = Dictionary(uniqueKeysWithValues: snapshot.entries.enumerated().map { ($0.element.id, $0.offset) })
        try transaction {
            for id in saved.keys where current[id] == nil { try delete(id) }
            for (position, entry) in snapshot.entries.enumerated() {
                if saved[entry.id] != entry { try upsert(entry, position: position) }
                else if savedPositions[entry.id] != position { try updatePosition(entry.id, position: position) }
            }
            if snapshot.collections != savedCollections {
                try run("INSERT OR REPLACE INTO state VALUES('collections',?)", [], data: JSONEncoder().encode(snapshot.collections))
            }
        }
        saved = current
        savedPositions = positions
        savedCollections = snapshot.collections
        tightenPermissions()
    }

    private func upsert(_ entry: ClipboardHistoryEntry, position: Int) throws {
        let values = [entry.id.uuidString, "\(position)", "\(entry.copiedAt.timeIntervalSince1970)", entry.kind.rawValue,
                      ClipboardHistorySearch.normalized(entry.sourceApp ?? "")]
        try run("INSERT INTO clips VALUES(?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET position=excluded.position,copied=excluded.copied,kind=excluded.kind,source=excluded.source,payload=excluded.payload", values, data: JSONEncoder().encode(entry))
        try run("DELETE FROM search WHERE rowid=(SELECT rowid FROM clips WHERE id=?)", [entry.id.uuidString])
        let searchable = [entry.title, entry.text, entry.filePaths.joined(separator: " "), entry.recognizedText,
                          entry.sourceApp ?? "", entry.sourceBundleID ?? "", entry.kind.rawValue, entry.imageDimensionsLabel].joined(separator: " ")
        try run("INSERT INTO search(rowid,id,body) SELECT rowid,?,? FROM clips WHERE id=?",
                [entry.id.uuidString, ClipboardHistorySearch.normalized(searchable), entry.id.uuidString])
    }

    private func delete(_ id: UUID) throws {
        try run("DELETE FROM search WHERE rowid=(SELECT rowid FROM clips WHERE id=?)", [id.uuidString])
        try run("DELETE FROM clips WHERE id=?", [id.uuidString])
    }

    private func updatePosition(_ id: UUID, position: Int) throws {
        try run("UPDATE clips SET position=? WHERE id=?", ["\(position)", id.uuidString])
    }

    func search(_ query: String, limit: Int = 50_000) throws -> [UUID] {
        let parsed = ClipboardLibraryQuery(query)
        var conditions: [String] = []
        var arguments: [String] = []
        let indexed = parsed.terms.filter { $0.count >= 3 }
        if !indexed.isEmpty {
            conditions.append("s.body MATCH ?")
            arguments.append(indexed.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: " AND "))
        }
        for term in parsed.terms where term.count < 3 {
            conditions.append("s.body LIKE ? ESCAPE '\\'")
            arguments.append("%" + term.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_") + "%")
        }
        if let kind = parsed.kind { conditions.append("c.kind=?"); arguments.append(kind) }
        if let app = parsed.app { conditions.append("c.source LIKE ?"); arguments.append("%\(app)%") }
        if let after = parsed.after { conditions.append("c.copied>=?"); arguments.append("\(after.timeIntervalSince1970)") }
        if let before = parsed.before { conditions.append("c.copied<?"); arguments.append("\(before.timeIntervalSince1970)") }
        let filter = conditions.isEmpty ? "" : " WHERE " + conditions.joined(separator: " AND ")
        var result: [UUID] = []
        try rows("SELECT c.id FROM search s JOIN clips c ON c.id=s.id" + filter + " ORDER BY c.copied DESC, c.position LIMIT \(max(1, limit))", arguments) { statement in
            if let id = UUID(uuidString: string(statement, 0)) { result.append(id) }
        }
        return result
    }

    func integrityCheck() throws {
        var valid = false
        try rows("PRAGMA quick_check") { valid = string($0, 0) == "ok" }
        guard valid else { throw ClipboardLibraryError.invalidArchive }
    }

    func backup(to destination: URL) throws {
        var target: OpaquePointer?
        guard sqlite3_open(destination.path, &target) == SQLITE_OK else { throw failure() }
        defer { sqlite3_close(target) }
        guard let backup = sqlite3_backup_init(target, "main", db, "main") else { throw failure() }
        let status = sqlite3_backup_step(backup, -1)
        let finish = sqlite3_backup_finish(backup)
        guard status == SQLITE_DONE, finish == SQLITE_OK else { throw failure() }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }

    func checkpoint() throws { try execute("PRAGMA wal_checkpoint(TRUNCATE)") }

    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do { try body(); try execute("COMMIT") }
        catch { try? execute("ROLLBACK"); throw error }
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }

    private func run(_ sql: String, _ values: [String], data: Data? = nil) throws {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        if let data {
            _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, Int32(values.count + 1), $0.baseAddress, Int32(data.count), transient) }
        }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
    }

    private func rows(_ sql: String, _ values: [String] = [], body: (OpaquePointer) throws -> Void) throws {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW { try body(statement); status = sqlite3_step(statement) }
        guard status == SQLITE_DONE else { throw failure() }
    }

    private func prepare(_ sql: String, _ values: [String]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw failure() }
        for (index, value) in values.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, transient)
        }
        return statement
    }

    private func blob(_ statement: OpaquePointer, _ column: Int32) -> Data {
        guard let bytes = sqlite3_column_blob(statement, column) else { return Data() }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
    }

    private func string(_ statement: OpaquePointer, _ column: Int32) -> String {
        sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
    }

    private func failure() -> Error {
        // SQLite diagnostics describe storage failures, never query or content.
        ClipboardLibraryError.storage(db.map { String(cString: sqlite3_errmsg($0)) } ?? "Clipboard storage unavailable.")
    }

    private func tightenPermissions() {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: databaseURL.path + suffix)
        }
    }
}

struct ClipboardLibraryQuery {
    var terms: [String] = []
    var kind: String?
    var app: String?
    var after: Date?
    var before: Date?

    init(_ query: String) {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd"
        for token in ClipboardHistorySearch.normalized(query).split(whereSeparator: \.isWhitespace).map(String.init) {
            let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { terms.append(token); continue }
            switch parts[0] {
            case "type" where ["text", "image", "files"].contains(parts[1]): kind = parts[1]
            case "app": app = parts[1]
            case "after": after = format.date(from: parts[1])
            case "before": before = format.date(from: parts[1])
            default: terms.append(token)
            }
        }
    }
}

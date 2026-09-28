// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CryptoKit
import Foundation

struct ClipboardLibraryManifest: Codable {
    var version = 1
    var createdAt = Date()
    var entryCount: Int
    var checksums: [String: String]
    var unavailable: [String]
}

enum ClipboardLibraryArchive {
    static func checksum(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func assetNames(_ entries: [ClipboardHistoryEntry]) -> Set<String> {
        Set(entries.compactMap(\.imageFile) + entries.flatMap { $0.representations.values })
    }

    static func safeAsset(_ name: String, in root: URL) throws -> URL {
        guard !name.isEmpty, name == (name as NSString).lastPathComponent, name != ".", name != ".." else {
            throw ClipboardLibraryError.invalidArchive
        }
        if FileManager.default.fileExists(atPath: root.path) {
            let parent = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard parent.isDirectory == true, parent.isSymbolicLink != true else { throw ClipboardLibraryError.invalidArchive }
        }
        let url = root.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { throw ClipboardLibraryError.invalidArchive }
        }
        return url
    }

    static func export(store: ClipboardLibraryStore, snapshot: ClipboardLibrarySnapshot, to destination: URL) throws {
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".clipboard-" + UUID().uuidString)
        guard PrivateFileStore.createDirectory(at: staging, container: staging) else { throw ClipboardLibraryError.invalidArchive }
        defer { try? FileManager.default.removeItem(at: staging) }
        try store.backup(to: staging.appendingPathComponent("ClipboardLibrary.sqlite"))
        let unavailable = try copyAssets(snapshot.entries, from: store.root.appendingPathComponent("ClipboardImages"), to: staging.appendingPathComponent("ClipboardImages"))
        var checksums: [String: String] = [:]
        checksums["ClipboardLibrary.sqlite"] = try checksum(Data(contentsOf: staging.appendingPathComponent("ClipboardLibrary.sqlite")))
        for name in assetNames(snapshot.entries).subtracting(unavailable) {
            let path = "ClipboardImages/" + name
            checksums[path] = try checksum(Data(contentsOf: staging.appendingPathComponent(path)))
        }
        let manifest = ClipboardLibraryManifest(entryCount: snapshot.entries.count, checksums: checksums, unavailable: unavailable.sorted())
        guard PrivateFileStore.write(try JSONEncoder().encode(manifest), to: staging.appendingPathComponent("manifest.json")) else {
            throw ClipboardLibraryError.invalidArchive
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw ClipboardLibraryError.storage("Choose a new backup filename.") }
        try FileManager.default.moveItem(at: staging, to: destination)
    }

    static func inspect(_ archive: URL) throws -> ClipboardLibraryManifest {
        let manifestURL = try safeAsset("manifest.json", in: archive)
        let manifest = try JSONDecoder().decode(ClipboardLibraryManifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.version == 1, manifest.checksums["ClipboardLibrary.sqlite"] != nil else { throw ClipboardLibraryError.invalidArchive }
        for (path, expected) in manifest.checksums {
            let url: URL
            if path == "ClipboardLibrary.sqlite" { url = try safeAsset(path, in: archive) }
            else if path.hasPrefix("ClipboardImages/") {
                url = try safeAsset(String(path.dropFirst("ClipboardImages/".count)), in: archive.appendingPathComponent("ClipboardImages"))
            } else { throw ClipboardLibraryError.invalidArchive }
            guard try checksum(Data(contentsOf: url)) == expected else { throw ClipboardLibraryError.invalidArchive }
        }
        return manifest
    }

    static func read(_ archive: URL, staging: URL) throws -> ClipboardLibrarySnapshot {
        let manifest = try inspect(archive)
        guard PrivateFileStore.createDirectory(at: staging, container: staging) else { throw ClipboardLibraryError.invalidArchive }
        let database = try Data(contentsOf: archive.appendingPathComponent("ClipboardLibrary.sqlite"))
        guard PrivateFileStore.write(database, to: staging.appendingPathComponent("ClipboardLibrary.sqlite")) else { throw ClipboardLibraryError.invalidArchive }
        let store = try ClipboardLibraryStore(root: staging)
        let snapshot = try store.load()
        guard snapshot.entries.count == manifest.entryCount else { throw ClipboardLibraryError.invalidArchive }
        let expected = assetNames(snapshot.entries)
        let included = Set(manifest.checksums.keys.filter { $0.hasPrefix("ClipboardImages/") }.map { String($0.dropFirst(16)) })
        guard expected == included.union(manifest.unavailable) else { throw ClipboardLibraryError.invalidArchive }
        return snapshot
    }

    @discardableResult
    static func copyAssets(_ entries: [ClipboardHistoryEntry], from source: URL, to destination: URL) throws -> Set<String> {
        guard PrivateFileStore.createDirectory(at: destination, container: destination) else { throw ClipboardLibraryError.invalidArchive }
        var unavailable: Set<String> = []
        for name in assetNames(entries) {
            let original = try safeAsset(name, in: source)
            guard FileManager.default.fileExists(atPath: original.path) else { unavailable.insert(name); continue }
            let data = try Data(contentsOf: original)
            let target = try safeAsset(name, in: destination)
            if FileManager.default.fileExists(atPath: target.path) {
                guard try Data(contentsOf: target) == data else { throw ClipboardLibraryError.invalidArchive }
            } else if !PrivateFileStore.write(data, to: target) { throw ClipboardLibraryError.invalidArchive }
        }
        return unavailable
    }

    static func merge(_ incoming: ClipboardLibrarySnapshot, into existing: ClipboardLibrarySnapshot) -> ClipboardLibrarySnapshot {
        var byID = Dictionary(uniqueKeysWithValues: existing.entries.map { ($0.id, $0) })
        for entry in incoming.entries where byID[entry.id] == nil { byID[entry.id] = entry }
        // Existing UUID wins deliberately. New records never replace a newer local edit.
        var entries = byID.values.sorted { $0.copiedAt > $1.copiedAt }
        var collections = existing.collections
        for collection in incoming.collections {
            if let index = collections.firstIndex(where: { $0.id == collection.id }) {
                let known = Set(collections[index].entryIDs)
                collections[index].entryIDs += collection.entryIDs.filter { !known.contains($0) }
            } else { collections.append(collection) }
        }
        var membership: [UUID: [UUID]] = [:]
        for board in collections {
            for id in board.entryIDs { membership[id, default: []].append(board.id) }
        }
        for index in entries.indices { entries[index].collectionIDs = membership[entries[index].id] ?? [] }
        return ClipboardLibrarySnapshot(entries: entries, collections: collections)
    }
}

enum ClipboardLibraryMigration {
    static func decodeLegacy(_ data: Data) throws -> [ClipboardHistoryEntry] {
        guard var records = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw ClipboardLibraryError.invalidLegacy }
        for index in records.indices where records[index]["id"] == nil {
            let digest = ClipboardLibraryArchive.checksum(data + Data("\(index)".utf8))
            let hex = Array(digest.prefix(32))
            let groups = [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { String(hex[$0]) }
            records[index]["id"] = groups.joined(separator: "-")
        }
        return try JSONDecoder().decode([ClipboardHistoryEntry].self, from: JSONSerialization.data(withJSONObject: records))
    }

    private static func stageLegacy(_ data: Data, entries: [ClipboardHistoryEntry], source: URL,
                                    store: ClipboardLibraryStore, marker: String) throws {
        let safety = store.root.appendingPathComponent("LegacyMigration", isDirectory: true)
        guard PrivateFileStore.createDirectory(at: safety), PrivateFileStore.write(data, to: safety.appendingPathComponent(marker + ".json")) else { throw ClipboardLibraryError.invalidLegacy }
        try ClipboardLibraryArchive.copyAssets(entries, from: source.appendingPathComponent("ClipboardImages"), to: safety.appendingPathComponent("ClipboardImages"))
        try ClipboardLibraryArchive.copyAssets(entries, from: source.appendingPathComponent("ClipboardImages"), to: store.root.appendingPathComponent("ClipboardImages"))
    }

    static func importLegacy(at source: URL, into store: ClipboardLibraryStore) throws -> Int {
        let url = try ClipboardLibraryArchive.safeAsset("ClipboardHistory.json", in: source)
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        let marker = "legacy-" + ClipboardLibraryArchive.checksum(Data(source.path.utf8)) + ".complete"
        if FileManager.default.fileExists(atPath: store.root.appendingPathComponent(marker).path) { return 0 }
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard ClipboardHistoryEditing.canLoadEncodedHistory(byteCount: values.fileSize) else { throw ClipboardLibraryError.invalidLegacy }
        return try importData(Data(contentsOf: url), source: source, into: store, marker: marker)
    }

    static func importData(_ data: Data, source: URL, into store: ClipboardLibraryStore, marker: String) throws -> Int {
        if FileManager.default.fileExists(atPath: store.root.appendingPathComponent(marker).path) { return 0 }
        guard ClipboardHistoryEditing.canLoadEncodedHistory(byteCount: data.count) else { throw ClipboardLibraryError.invalidLegacy }
        var entries = try decodeLegacy(data)
        guard Set(entries.map(\.id)).count == entries.count else { throw ClipboardLibraryError.invalidLegacy }
        try stageLegacy(data, entries: entries, source: source, store: store, marker: marker)
        let current = try store.load()
        let pins = entries.filter(\.isPinned).map(\.id)
        let collection = ClipboardCollection(id: UUID(uuidString: "4F34B045-9CED-4AE3-8479-2B90677A4A19")!,
                                             name: FeatureStrings.clipboard(L10n.shared.language).pinned, entryIDs: pins)
        for index in entries.indices where entries[index].isPinned {
            entries[index].collectionIDs.append(collection.id)
        }
        let merged = ClipboardLibraryArchive.merge(.init(entries: entries, collections: pins.isEmpty ? [] : [collection]), into: current)
        try store.save(merged)
        let verified = try store.load()
        let localIDs = Set(current.entries.map(\.id))
        guard entries.filter({ !localIDs.contains($0.id) }).allSatisfy({ verified.entries.contains($0) }) else {
            throw ClipboardLibraryError.invalidLegacy
        }
        guard PrivateFileStore.write(Data("\(entries.count)".utf8), to: store.root.appendingPathComponent(marker)) else { throw ClipboardLibraryError.invalidLegacy }
        return entries.filter { !localIDs.contains($0.id) }.count
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

extension ClipboardHistoryService {
    func load() {
        Self.persistQueue.async { [weak self] in
            guard let root = ClipboardLibraryProbe.root ?? PrivateFileStore.containerURL else { return }
            do {
                let store = try ClipboardLibraryStore(root: root)
                var imported = ClipboardLibraryProbe.root == nil ? try ClipboardLibraryMigration.importLegacy(at: root, into: store) : 0
                if ClipboardLibraryProbe.root == nil, Bundle.main.bundleIdentifier == "io.github.xztyle.Aster" {
                    let legacy = root.deletingLastPathComponent().appendingPathComponent("com.vorssaint.utils")
                    imported += try ClipboardLibraryMigration.importLegacy(at: legacy, into: store)
                }
                if ClipboardLibraryProbe.root == nil { imported += try Self.importDefaults(into: store) }
                let snapshot = try store.load()
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.library = store
                    self.entries = snapshot.entries
                    self.collections = snapshot.collections
                    self.adoptLegacyPins()
                    self.libraryReady = true
                    self.migrationCount = imported
                    if ClipboardLibraryProbe.root == nil { self.trimToLimit() }
                    self.scheduleSearch()
                }
            } catch { DispatchQueue.main.async { self?.storageError = error.localizedDescription } }
        }
    }

    static func importDefaults(into store: ClipboardLibraryStore) throws -> Int {
        guard let own = Bundle.main.bundleIdentifier else { return 0 }
        let domains = own == "io.github.xztyle.Aster" ? [own, "com.vorssaint.utils"] : [own]
        var count = 0
        for domain in domains {
            let marker = "defaults-" + ClipboardLibraryArchive.checksum(Data(domain.utf8)) + ".complete"
            guard !FileManager.default.fileExists(atPath: store.root.appendingPathComponent(marker).path),
                  let data = UserDefaults.standard.persistentDomain(forName: domain)?[DefaultsKey.clipboardHistoryEntries] as? Data else { continue }
            let source = domain == own ? store.root : store.root.deletingLastPathComponent().appendingPathComponent(domain)
            count += try ClipboardLibraryMigration.importData(data, source: source, into: store, marker: marker)
        }
        // Both preference domains remain untouched for rollback.
        return count
    }

    func save() {
        guard libraryReady else { return }
        persistenceGeneration &+= 1
        guard !persistScheduled else { return }
        persistScheduled = true
        isSaving = true
        DispatchQueue.main.async { [weak self] in
            guard let self, self.persistScheduled else { return }
            self.persistScheduled = false
            self.persist()
        }
    }

    func persist() {
        guard let library else { return }
        let snapshot = ClipboardLibrarySnapshot(entries: entries, collections: collections)
        let generation = persistenceGeneration
        Self.persistQueue.async { [weak self] in
            do {
                try library.save(snapshot)
                DispatchQueue.main.async {
                    guard let self, generation == self.persistenceGeneration else { return }
                    self.isSaving = false
                    self.storageError = nil
                    self.scheduleSearch()
                    ClipboardImageStore.cleanup(keeping: ClipboardLibraryArchive.assetNames(self.entries),
                                                filePaths: Set(self.entries.flatMap(\.filePaths)))
                }
            } catch {
                DispatchQueue.main.async { self?.storageError = error.localizedDescription; self?.isSaving = false }
            }
        }
    }

    func flushBeforeTermination() {
        if persistScheduled { persistScheduled = false; persist() }
        Self.persistQueue.sync { try? library?.checkpoint() }
    }

    func scheduleSearch() {
        searchGeneration &+= 1
        guard !searchScheduled else { return }
        searchScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.searchScheduled = false
            self.performSearch()
        }
    }

    func performSearch() {
        let query = quickQuery
        let generation = searchGeneration
        let all = entries
        let collection = collections.first { $0.id == selectedCollectionID }
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let library else {
            quickResults = orderedResults(all, collection: collection)
            return
        }
        Self.persistQueue.async { [weak self] in
            do {
                let ids = Set(try library.search(query))
                DispatchQueue.main.async {
                    guard let self, self.searchGeneration == generation else { return }
                    self.quickResults = self.orderedResults(all.filter { ids.contains($0.id) }, collection: collection)
                }
            } catch { DispatchQueue.main.async { self?.storageError = error.localizedDescription } }
        }
    }

    func orderedResults(_ values: [ClipboardHistoryEntry], collection: ClipboardCollection?) -> [ClipboardHistoryEntry] {
        guard let collection else { return values.sorted { $0.copiedAt > $1.copiedAt } }
        let lookup = Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) })
        return collection.entryIDs.compactMap { lookup[$0] }
    }

    func ensureDefaultCollection() -> UUID {
        if let first = collections.first { return first.id }
        let collection = ClipboardCollection(name: FeatureStrings.clipboard(L10n.shared.language).pinned)
        collections.append(collection)
        return collection.id
    }

    func adoptLegacyPins() {
        let pins = entries.filter { $0.pinnedAt != nil && $0.collectionIDs.isEmpty }
        guard !pins.isEmpty else { return }
        let id = ensureDefaultCollection()
        for entry in pins { addToCollection(entry, id: id) }
        // load() sets ready after this conversion; persist the converted membership now.
        libraryReady = true
        save()
    }

    func createCollection(name: String, color: Int) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let collection = ClipboardCollection(name: String(name.prefix(80)), color: color)
        collections.append(collection)
        selectedCollectionID = collection.id
        save()
    }

    func updateCollection(_ collection: ClipboardCollection, name: String, color: Int) {
        guard let index = collections.firstIndex(where: { $0.id == collection.id }), !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        collections[index].name = String(name.prefix(80))
        collections[index].color = color
        save()
    }

    func moveCollection(_ collection: ClipboardCollection, delta: Int) {
        guard let index = collections.firstIndex(where: { $0.id == collection.id }), collections.indices.contains(index + delta) else { return }
        collections.swapAt(index, index + delta)
        save()
    }

    func deleteCollection(_ collection: ClipboardCollection) {
        collections.removeAll { $0.id == collection.id }
        for index in entries.indices {
            entries[index].collectionIDs.removeAll { $0 == collection.id }
            if entries[index].collectionIDs.isEmpty { entries[index].pinnedAt = nil }
        }
        selectedCollectionID = nil
        save()
    }

    func addToCollection(_ entry: ClipboardHistoryEntry, id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }),
              let board = collections.firstIndex(where: { $0.id == id }) else { return }
        if !entries[index].collectionIDs.contains(id) { entries[index].collectionIDs.append(id) }
        entries[index].pinnedAt = entries[index].pinnedAt ?? Date()
        if !collections[board].entryIDs.contains(entry.id) { collections[board].entryIDs.append(entry.id) }
        scheduleSearch()
        save()
    }

    func removeFromCollections(_ entry: ClipboardHistoryEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].collectionIDs = []
        entries[index].pinnedAt = nil
        for board in collections.indices { collections[board].entryIDs.removeAll { $0 == entry.id } }
        scheduleSearch()
        save()
    }

    func reorderInCollection(_ entry: ClipboardHistoryEntry, delta: Int) {
        guard let board = collections.firstIndex(where: { $0.id == selectedCollectionID }),
              let position = collections[board].entryIDs.firstIndex(of: entry.id),
              collections[board].entryIDs.indices.contains(position + delta) else { return }
        collections[board].entryIDs.swapAt(position, position + delta)
        scheduleSearch()
        save()
    }

    func rename(_ entry: ClipboardHistoryEntry, title: String) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].title = String(title.prefix(200))
        save()
    }

    func pause(for duration: TimeInterval?) {
        pausedUntil = duration.map { $0.isFinite ? Date().addingTimeInterval($0) : Date.distantFuture }
        if ClipboardLibraryProbe.root == nil {
            UserDefaults.standard.set(pausedUntil?.timeIntervalSince1970, forKey: "clipboardCapturePausedUntil")
        }
        captureState.restart()
        latestPasteboardEntry = nil
    }

    func applyRetention(days: Int) {
        UserDefaults.standard.set(max(0, days), forKey: DefaultsKey.clipboardRetentionDays)
        trimToLimit()
    }

    func retentionRemovals(days: Int) -> [ClipboardHistoryEntry] {
        guard days > 0 else { return [] }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        return entries.filter { !$0.isPinned && $0.copiedAt < cutoff }
    }
}

extension ClipboardHistoryService {
    func retentionByteCount(days: Int) -> Int64 {
        let removals = retentionRemovals(days: days)
        let text = removals.reduce(Int64(0)) { $0 + Int64($1.text.utf8.count) }
        guard let directory = ClipboardImageStore.directory else { return text }
        return ClipboardLibraryArchive.assetNames(removals).reduce(text) { total, name in
            guard let url = try? ClipboardLibraryArchive.safeAsset(name, in: directory),
                  let values = try? url.resourceValues(forKeys: [.fileSizeKey]) else { return total }
            return total + Int64(values.fileSize ?? 0)
        }
    }
}

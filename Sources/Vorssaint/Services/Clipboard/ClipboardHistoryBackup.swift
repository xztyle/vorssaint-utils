// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

extension ClipboardHistoryService {
    func exportLibrary() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Clipboard-\(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-" )).asterclipboard"
        panel.message = ClipboardLibraryStrings.current.privateArchive
        guard panel.runModal() == .OK, let url = panel.url else { return }
        flushBeforeTermination()
        guard let library else { return }
        let snapshot = ClipboardLibrarySnapshot(entries: entries, collections: collections)
        Self.persistQueue.async { [weak self] in
            do { try ClipboardLibraryArchive.export(store: library, snapshot: snapshot, to: url) }
            catch { DispatchQueue.main.async { self?.storageError = error.localizedDescription } }
        }
    }

    func chooseRestoreLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = ClipboardLibraryStrings.current.restoreLibrary
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Self.persistQueue.async { [weak self] in
            do {
                let manifest = try ClipboardLibraryArchive.inspect(url)
                DispatchQueue.main.async { self?.confirmRestore(url, manifest: manifest) }
            } catch { DispatchQueue.main.async { self?.storageError = error.localizedDescription } }
        }
    }

    func confirmRestore(_ url: URL, manifest: ClipboardLibraryManifest) {
        let strings = ClipboardLibraryStrings.current
        let alert = NSAlert()
        alert.messageText = strings.restoreLibrary
        alert.informativeText = "\(manifest.entryCount) · \(strings.collections)\n\(strings.unavailable): \(manifest.unavailable.count)\n\(strings.privateArchive)"
        alert.addButton(withTitle: strings.merge)
        alert.addButton(withTitle: strings.replace)
        alert.addButton(withTitle: FeatureStrings.clipboard(L10n.shared.language).cancel)
        let response = alert.runModal()
        guard response != .alertThirdButtonReturn else { return }
        restoreLibrary(from: url, replacing: response == .alertSecondButtonReturn)
    }

    func restoreLibrary(from archive: URL, replacing: Bool) {
        flushBeforeTermination()
        guard let library else { return }
        let previous = ClipboardLibrarySnapshot(entries: entries, collections: collections)
        libraryReady = false
        isSaving = true
        captureState.restart()
        Self.persistQueue.async { [weak self] in
            do {
                let result = try Self.restore(archive, store: library, previous: previous, replacing: replacing)
                DispatchQueue.main.async {
                    self?.entries = result.snapshot.entries
                    self?.collections = result.snapshot.collections
                    self?.libraryReady = true
                    self?.isSaving = false
                    self?.storageError = result.warning
                    self?.scheduleSearch()
                    ClipboardImageStore.cleanup(keeping: ClipboardLibraryArchive.assetNames(result.snapshot.entries),
                                                filePaths: Set(result.snapshot.entries.flatMap(\.filePaths)))
                }
            } catch {
                DispatchQueue.main.async { self?.libraryReady = true; self?.isSaving = false; self?.storageError = error.localizedDescription }
            }
        }
    }

    static func restore(_ archive: URL, store: ClipboardLibraryStore, previous: ClipboardLibrarySnapshot,
                        replacing: Bool) throws -> (snapshot: ClipboardLibrarySnapshot, warning: String?) {
        let staging = store.root.appendingPathComponent("Restore-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staging) }
        let incoming = try ClipboardLibraryArchive.read(archive, staging: staging)
        try rollingBackup(store: store, snapshot: previous)
        try ClipboardLibraryArchive.copyAssets(incoming.entries, from: archive.appendingPathComponent("ClipboardImages"),
                                               to: store.root.appendingPathComponent("ClipboardImages"))
        let result = replacing ? incoming : ClipboardLibraryArchive.merge(incoming, into: previous)
        try store.save(result)
        let verified = try store.load()
        guard Set(verified.entries.map(\.id)) == Set(result.entries.map(\.id)),
              verified.collections == result.collections else { throw ClipboardLibraryError.invalidArchive }
        do { try rollingBackup(store: store, snapshot: verified); return (verified, nil) }
        catch { return (verified, error.localizedDescription) }
    }

    static func rollingBackup(store: ClipboardLibraryStore, snapshot: ClipboardLibrarySnapshot) throws {
        let directory = store.root.appendingPathComponent("ClipboardBackups")
        guard PrivateFileStore.createDirectory(at: directory) else { throw ClipboardLibraryError.invalidArchive }
        let name = String(Int(Date().timeIntervalSince1970)) + "-" + UUID().uuidString + ".asterclipboard"
        try ClipboardLibraryArchive.export(store: store, snapshot: snapshot, to: directory.appendingPathComponent(name))
        let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "asterclipboard" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        for expired in backups.dropFirst(3) { try FileManager.default.removeItem(at: expired) }
    }
}

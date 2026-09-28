// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import SwiftUI

extension ClipboardHistoryService {
    func copy(_ entry: ClipboardHistoryEntry, completion: @escaping (Bool) -> Void) {
        writeToPasteboard([entry]) { [weak self] copied in
            if copied {
                self?.touch([entry.id])
                self?.latestPasteboardEntry = entry
            }
            completion(copied)
        }
    }

    func copy(_ selectedEntries: [ClipboardHistoryEntry], completion: @escaping (Bool) -> Void) {
        guard !selectedEntries.isEmpty else {
            completion(false)
            return
        }
        writeToPasteboard(selectedEntries) { [weak self] copied in
            if copied {
                self?.touch(selectedEntries.map(\.id))
                // A single-entry selection mirrors the entry above; a real
                // batch no longer matches any one saved entry's text, so the
                // menu bar preview goes blank instead of keeping a stale
                // single-entry snapshot on display.
                self?.latestPasteboardEntry = selectedEntries.count == 1 ? selectedEntries[0] : nil
            }
            completion(copied)
        }
    }

    /// Failure includes an expired request. The lane remains serialized and
    /// admission stays occupied until the underlying operation actually ends.
    func writeToPasteboard(_ list: [ClipboardHistoryEntry],
                                   completion: @escaping (Bool) -> Void) {
        guard !copyInFlight, let write = Self.plannedWrite(for: list) else {
            completion(false)
            return
        }
        copyInFlight = true
        GeneralPasteboardAccess.shared.async(timeout: Self.pasteboardTimeout, { isExpired in
            write.write(to: ClipboardLibraryProbe.root == nil ? NSPasteboard.general
                        : NSPasteboard(name: NSPasteboard.Name("io.github.xztyle.Aster.clipboard-fixture")),
                        isExpired: isExpired)
        }, then: { result in
            completion(result?.succeeded == true)
            ClipboardLibraryProbe.recordState()
        }, didFinish: { [weak self] result in
            guard let self else { return }
            self.copyInFlight = false
            // Consume our mutation even if result delivery already expired.
            // This also excludes a partial write whose required format failed.
            if let result {
                self.lastChangeCount = max(self.lastChangeCount, result.changeCount)
            }
        })
    }

    /// What to put on the pasteboard once it is cleared, or nil when the
    /// content is gone (image purged from the store, files deleted or on an
    /// ejected volume) and the copy must abort with the user's clipboard
    /// intact. Resolving on the caller's thread also keeps the AppKit work a
    /// write may need — RTFD attachments, TIFF rendering — on the main thread
    /// it has always run on; only the pasteboard calls move to the lane.
    static func plannedWrite(for list: [ClipboardHistoryEntry])
        -> ClipboardHistoryWrite? {
        if list.count == 1, let entry = list.first {
            switch entry.kind {
            case .text:
                guard !entry.representations.isEmpty else { return .text(entry.text) }
                var formats: [String: Data] = [:]
                for (type, name) in entry.representations {
                    guard let data = ClipboardImageStore.imageData(named: name) else { return nil }
                    formats[type] = data
                }
                return .representations(plain: entry.text, formats: formats)
            case .image:
                guard let name = entry.imageFile,
                      let data = ClipboardImageStore.imageData(named: name) else { return nil }
                // TIFF alongside PNG: some paste targets only take TIFF.
                let tiff = entry.representations[NSPasteboard.PasteboardType.tiff.rawValue]
                    .flatMap { ClipboardImageStore.imageData(named: $0) } ?? NSBitmapImageRep(data: data)?.tiffRepresentation
                return .image(png: data, tiff: tiff)
            case .files:
                let urls = entry.filePaths
                    .map { URL(fileURLWithPath: $0) }
                    .filter { FileManager.default.fileExists(atPath: $0.path) }
                guard !urls.isEmpty, urls.count == entry.filePaths.count else { return nil }
                return .files(urls as [NSURL])
            }
        }

        // Batches: an all-files selection pastes as the files themselves; a
        // selection with images pastes as rich text with the images embedded;
        // anything else combines as text (files contribute paths).
        switch ClipboardHistoryBatch.pasteMode(for: list) {
        case let .files(paths):
            let urls = paths.map { URL(fileURLWithPath: $0) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
            guard !urls.isEmpty, urls.count == paths.count else { return nil }
            return .files(urls as [NSURL])
        case let .text(combined):
            return .text(combined)
        case let .rich(parts):
            guard let rich = richBatchAttributedString(parts) else { return nil }
            let plain = ClipboardHistoryBatch.richPlainText(parts)
            return .rich(rich, plain: plain)
        case nil:
            guard let first = list.first else { return nil }
            return plannedWrite(for: [first])
        }
    }

    /// Text and images interleaved in list order, as one attributed string:
    /// rich targets (Notes, Mail, TextEdit) paste everything together. Image
    /// attachments travel as PNG file wrappers, which RTFD serializes intact.
    /// A selected image whose stored payload is gone aborts the whole write
    /// (returns nil), keeping the same invariant as the single-entry path:
    /// stale content never silently vanishes from a paste after the user's
    /// clipboard was already overwritten.
    static func richBatchAttributedString(_ parts: [ClipboardHistoryBatch.RichPart])
        -> NSAttributedString? {
        let result = NSMutableAttributedString()
        for part in parts {
            switch part {
            case let .text(text):
                result.append(NSAttributedString(string: text + "\n"))
            case let .image(name):
                guard let data = ClipboardImageStore.imageData(named: name) else { return nil }
                let wrapper = FileWrapper(regularFileWithContents: data)
                wrapper.preferredFilename = name
                let attachment = NSTextAttachment(fileWrapper: wrapper)
                result.append(NSAttributedString(attachment: attachment))
                result.append(NSAttributedString(string: "\n"))
            }
        }
        return result.length > 0 ? result : nil
    }

    func touch(_ entryIDs: [UUID]) {
        var didUpdate = false
        let now = Date()
        for entryID in entryIDs {
            if let index = entries.firstIndex(where: { $0.id == entryID }) {
                entries[index].copiedAt = now
                entries[index].copyCount += 1
                didUpdate = true
            }
        }
        if didUpdate {
            save()
        }
    }


}

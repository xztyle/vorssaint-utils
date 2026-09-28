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
import Vision

extension ClipboardHistoryService {
    func start() {
        guard ClipboardLibraryProbe.root == nil else { return }
        guard timer == nil else {
            isRunning = true
            return
        }
        let timer = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.captureIfChanged()
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        isRunning = true
        ClipboardIgnoredApps.shared.setHistoryRunning(true)
        captureState.restart()
        captureIfChanged()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        ClipboardIgnoredApps.shared.setHistoryRunning(false)
        captureState.invalidate()
        // Otherwise the last known copy keeps showing in the menu bar preview
        // for the moment between history starting to watch again and the
        // baseline check actually answering, instead of going blank right
        // away like the rest of the feature does while stopped.
        latestPasteboardEntry = nil
    }

    /// What the background pasteboard read hands back to the main thread.
    enum CapturedContent {
        case rejected
        case files([String])
        case image((data: Data, width: Int, height: Int, originalTIFF: Data?))
        case text(String, [String: Data])
    }

    func captureIfChanged() {
        guard isRunning, libraryReady, !pauseIsActive, let generation = captureState.begin() else { return }
        let baseline = captureState.needsBaseline
        let since = lastChangeCount
        let skipRead = ClipboardIgnoredApps.shared.currentSourceIsExcluded
        let rich = UserDefaults.standard.bool(forKey: DefaultsKey.clipboardHistoryIncludeImagesFiles)
        GeneralPasteboardAccess.shared.async(timeout: Self.pasteboardTimeout, { expired -> CaptureResult? in
            let count = NSPasteboard.general.changeCount
            guard !expired() else { return nil }
            let content = !skipRead && (baseline || count != since) ? Self.readPasteboard(includeImagesFiles: rich) : nil
            return (count, content)
        }, then: { [weak self] result in
            self?.receiveCapture(result, generation: generation, baseline: baseline, since: since)
        }, didFinish: { [weak self] _ in self?.captureState.finish() })
    }

    typealias CaptureResult = (changeCount: Int, content: CapturedContent?)

    func receiveCapture(_ result: CaptureResult?, generation: Int, baseline: Bool, since: Int) {
        guard let result else { captureState.expire(generation); return }
        guard isRunning, captureState.accepts(generation) else { return }
        if baseline {
            lastChangeCount = result.changeCount
            captureState.didBaseline()
            latestPasteboardEntry = result.content.flatMap(matchingEntry)
            return
        }
        let excluded = ClipboardIgnoredApps.shared.excludedSourceSinceLastCheck()
        guard let accepted = ClipboardHistoryChangeCount.accepted(read: result.changeCount, since: since, last: lastChangeCount) else { return }
        lastChangeCount = accepted
        latestPasteboardEntry = nil
        guard !excluded, let content = result.content else { return }
        switch content {
        case .rejected: storageError = ClipboardLibraryStrings.current.saveFailure
        case .files(let paths): promoteFiles(paths)
        case .image(let image): promoteImage(image)
        case .text(let text, let representations): promote(text, representations: representations)
        }
    }

    /// The saved entry, if any, whose content is exactly what was just read
    /// off the pasteboard — the same field comparisons promote/promoteImage/
    /// promoteFiles use to recognize a re-copy of something already saved.
    func matchingEntry(for content: CapturedContent) -> ClipboardHistoryEntry? {
        switch content {
        case .rejected: return nil
        case .text(let text, _):
            return entries.first(where: { $0.kind == .text && $0.text == text })
        case .image(let image):
            let hash = Self.sha256Hex(image.data)
            return entries.first(where: { $0.kind == .image && $0.imageHash == hash })
        case .files(let paths):
            return entries.first(where: { $0.kind == .files && $0.filePaths == paths })
        }
    }

    /// Runs on the shared pasteboard lane: everything in here may block behind
    /// the pasteboard server, which is exactly why it stays off the main thread.
    static func readPasteboard(includeImagesFiles: Bool) -> CapturedContent? {
        let pasteboard = NSPasteboard.general
        let types = pasteboard.types ?? []
        guard !ClipboardHistorySensitiveText.isConcealed(types.map(\.rawValue)) else { return nil }
        if includeImagesFiles, let content = readRichMedia(pasteboard) { return content }
        guard let text = ClipboardHistoryPasteboardText.preferredText(
            webURLString: webURLString(from: pasteboard), plainText: plainText(from: pasteboard)) else { return nil }
        var formats: [String: Data] = [:]
        for type in [NSPasteboard.PasteboardType.rtf, .rtfd, .html] {
            if let data = pasteboard.data(forType: type) {
                guard data.count <= maxRawImageBytes else { return .rejected }
                formats[type.rawValue] = data
            }
        }
        return .text(text, formats)
    }

    static func readRichMedia(_ pasteboard: NSPasteboard) -> CapturedContent? {
        if let paths = copiedFilePaths(from: pasteboard) {
            if ClipboardHistoryCapturePolicy.isCopiedScreenshot(paths, in: ScreenshotSupport.copiedFilesDirectory()) {
                return copiedPNGImage(from: pasteboard).map(CapturedContent.image) ?? .rejected
            }
            return .files(paths)
        }
        if let image = copiedPNGImage(from: pasteboard) { return .image(image) }
        if !(Set(pasteboard.types ?? []).isDisjoint(with: [.png, .tiff, .fileURL])) { return .rejected }
        return nil
    }

    static func plainText(from pasteboard: NSPasteboard) -> String? {
        if let plain = pasteboard.string(forType: .string) { return plain }
        if let data = pasteboard.data(forType: .rtfd), data.count <= maxRawImageBytes {
            return NSAttributedString(rtfd: data, documentAttributes: nil)?.string
        }
        if let data = pasteboard.data(forType: .rtf), data.count <= maxRawImageBytes {
            return NSAttributedString(rtf: data, documentAttributes: nil)?.string
        }
        if let html = pasteboard.string(forType: .html), html.utf8.count <= maxRawImageBytes {
            return html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
        }
        return nil
    }

    static var maxCopiedFiles: Int { 100 }
    static var maxImageBytes: Int { 16 * 1024 * 1024 }
    static var maxRawImageBytes: Int { 64 * 1024 * 1024 }

    static func copiedFilePaths(from pasteboard: NSPasteboard) -> [String]? {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                                options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty,
              urls.count <= maxCopiedFiles
        else { return nil }
        return urls.map { $0.standardizedFileURL.path }
    }

    static func copiedPNGImage(from pasteboard: NSPasteboard)
        -> (data: Data, width: Int, height: Int, originalTIFF: Data?)? {
        let png = pasteboard.data(forType: .png)
        guard let source = png ?? pasteboard.data(forType: .tiff),
              source.count <= (png == nil ? maxRawImageBytes : maxImageBytes),
              let rep = NSBitmapImageRep(data: source),
              rep.pixelsWide > 0, rep.pixelsHigh > 0
        else { return nil }
        let data: Data
        if let png {
            data = png
        } else if let converted = rep.representation(using: .png, properties: [:]) {
            data = converted
        } else {
            return nil
        }
        guard data.count <= maxImageBytes else { return nil }
        return (data, rep.pixelsWide, rep.pixelsHigh, png == nil ? source : nil)
    }

    func promoteImage(_ image: (data: Data, width: Int, height: Int, originalTIFF: Data?)) {
        let hash = Self.sha256Hex(image.data)
        var entry: ClipboardHistoryEntry
        if let existing = entries.first(where: { $0.kind == .image && $0.imageHash == hash }) {
            entry = existing
        } else {
            guard let name = ClipboardImageStore.store(image.data) else {
                storageError = ClipboardLibraryStrings.current.saveFailure
                return
            }
            entry = ClipboardHistoryEntry(text: "", kind: .image, imageFile: name,
                                          imageHash: hash, imageWidth: image.width, imageHeight: image.height)
        }
        if let original = image.originalTIFF {
            guard let name = ClipboardImageStore.storeRepresentation(original, type: NSPasteboard.PasteboardType.tiff.rawValue) else {
                storageError = ClipboardLibraryStrings.current.saveFailure
                return
            }
            entry.representations[NSPasteboard.PasteboardType.tiff.rawValue] = name
        }
        promoteEntry(entry)
        recognizeImage(entry, data: image.data)
    }

    func promoteFiles(_ paths: [String]) {
        let entry = entries.first(where: { $0.kind == .files && $0.filePaths == paths })
            ?? ClipboardHistoryEntry(text: "", kind: .files, filePaths: paths)
        promoteEntry(entry)
    }

    func promoteEntry(_ candidate: ClipboardHistoryEntry) {
        var entry = candidate
        if entries.contains(where: { $0.id == entry.id }) { entry.copyCount += 1 }
        entries.removeAll { $0.id == entry.id }
        entry.copiedAt = Date()
        entry.sourceApp = ClipboardIgnoredApps.shared.lastConfidentSource?.name
        entry.sourceBundleID = ClipboardIgnoredApps.shared.lastConfidentSource?.id
        insertPromoted(entry)
        trimToLimit()
        save()
    }

    func recognizeImage(_ entry: ClipboardHistoryEntry, data: Data) {
        guard entry.recognizedText.isEmpty else { return }
        Self.ocrQueue.async { [weak self] in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            guard (try? VNImageRequestHandler(data: data).perform([request])) != nil else { return }
            let text = request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n") ?? ""
            DispatchQueue.main.async {
                guard let self, self.isRunning, let index = self.entries.firstIndex(where: { $0.id == entry.id }) else { return }
                self.entries[index].recognizedText = text
                self.save()
            }
        }
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func webURLString(from pasteboard: NSPasteboard) -> String? {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
        if let url = urls?.first(where: { isWebURL($0) }) {
            return url.absoluteString
        }
        for type in [NSPasteboard.PasteboardType("public.url"),
                     NSPasteboard.PasteboardType("NSURLPboardType")] {
            if let value = pasteboard.string(forType: type),
               let url = URL(string: value),
               isWebURL(url) {
                return url.absoluteString
            }
        }
        return nil
    }

    static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host != nil
    }

    func promote(_ raw: String, representations: [String: Data]) {
        guard let text = ClipboardHistoryEditing.storableText(raw) else {
            storageError = ClipboardLibraryStrings.current.saveFailure
            return
        }
        if UserDefaults.standard.bool(forKey: DefaultsKey.clipboardHistorySkipSensitive), looksSensitive(text) { return }
        var names: [String: String] = [:]
        for (type, data) in representations {
            guard let name = ClipboardImageStore.storeRepresentation(data, type: type) else {
                storageError = ClipboardLibraryStrings.current.saveFailure
                return
            }
            names[type] = name
        }
        var entry = entries.first { $0.kind == .text && $0.text == text && $0.representations == names }
            ?? ClipboardHistoryEntry(text: text)
        entry.representations = names
        promoteEntry(entry)
    }

}

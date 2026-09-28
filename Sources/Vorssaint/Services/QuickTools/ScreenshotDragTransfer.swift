// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The byte and file representations are made from the same committed export.
/// Provider callbacks retain the bytes and can recreate a file for late readers.
struct ScreenshotDragTransfer {
    let png: Data
    let tiff: Data?
    let name: String
    let directory: URL?

    init?(image: CGImage, scale: CGFloat, prefix: String, directory: URL? = nil) {
        guard let png = ScreenshotRenderer.pngData(from: image, scale: scale) else { return nil }
        self.directory = directory
        self.png = png
        tiff = ScreenshotRenderer.tiffData(from: image, scale: scale)
        name = ScreenshotSupport.fileName(prefix: prefix, date: Date())
    }

    static var temporaryDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "io.github.xztyle.Aster", isDirectory: true)
            .appendingPathComponent("CaptureTransfers", isDirectory: true)
    }

    static func removeExpiredFiles(now: Date = Date()) {
        let root = temporaryDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.creationDateKey, .isSymbolicLinkKey]),
              (try? root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { return }
        for file in files where file.lastPathComponent.hasPrefix("ScreenshotDrag-") {
            guard let values = try? file.resourceValues(forKeys: [.creationDateKey, .isSymbolicLinkKey]),
                  values.isSymbolicLink != true, let date = values.creationDate,
                  now.timeIntervalSince(date) > 48 * 3600 else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    func file() -> URL? {
        guard let url = try? ScreenshotSupport.temporaryDragFile(
            data: png, name: name, directory: directory ?? Self.temporaryDirectory) else { return nil }
        try? FileManager.default.setAttributes([.posixPermissions: 0o700],
                                              ofItemAtPath: url.deletingLastPathComponent().path)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    func itemProvider() -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = name
        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier,
                                             visibility: .all) { completion in
            completion(png, nil); return nil
        }
        if let tiff {
            provider.registerDataRepresentation(forTypeIdentifier: UTType.tiff.identifier,
                                                 visibility: .all) { completion in
                completion(tiff, nil); return nil
            }
        }
        provider.registerFileRepresentation(forTypeIdentifier: UTType.png.identifier,
                                             fileOptions: [], visibility: .all) { completion in
            completion(file(), false, nil); return nil
        }
        return provider
    }

    func pasteboardItem() -> NSPasteboardItem? {
        guard let url = file() else { return nil }
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        if let tiff { item.setData(tiff, forType: .tiff) }
        item.setString(url.absoluteString, forType: .fileURL)
        return item
    }
}

/// AppKit supplies the end/cancel callback missing from SwiftUI's onDrag API.
struct ScreenshotPreviewDragSurface: NSViewRepresentable {
    let image: CGImage
    let transfer: () -> ScreenshotDragTransfer?
    let edit: () -> Void
    let dragging: (Bool) -> Void

    func makeNSView(context: Context) -> Surface { Surface() }
    func updateNSView(_ view: Surface, context: Context) {
        view.image = image
        view.transfer = transfer
        view.edit = edit
        view.dragging = dragging
    }

    final class Surface: NSView, NSDraggingSource {
        var image: CGImage?
        var transfer: (() -> ScreenshotDragTransfer?)?
        var edit: (() -> Void)?
        var dragging: ((Bool) -> Void)?
        private var down: NSEvent?
        private var started = false

        override func mouseDown(with event: NSEvent) { down = event; started = false }
        override func mouseUp(with event: NSEvent) {
            if !started { edit?() }
            down = nil
        }
        override func mouseDragged(with event: NSEvent) {
            guard !started, let down, let image,
                  hypot(event.locationInWindow.x - down.locationInWindow.x,
                        event.locationInWindow.y - down.locationInWindow.y) > 4,
                  let writer = transfer?()?.pasteboardItem() else { return }
            started = true
            dragging?(true)
            let item = NSDraggingItem(pasteboardWriter: writer)
            item.setDraggingFrame(bounds, contents: NSImage(cgImage: image, size: bounds.size))
            let session = beginDraggingSession(with: [item], event: down, source: self)
            session.animatesToStartingPositionsOnCancelOrFail = true
        }
        func draggingSession(_ session: NSDraggingSession,
                             sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
        func draggingSession(_ session: NSDraggingSession, endedAt point: NSPoint,
                             operation: NSDragOperation) {
            down = nil
            dragging?(false)
        }
    }
}

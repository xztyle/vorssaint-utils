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

/// File-backed storage for copied images: PNGs live in Application Support
/// (UserDefaults would balloon with base64), named by UUID and swept against
/// the live entry list after every save.
enum ClipboardImageStore {
    /// Explicit limits: NSCache only sheds under system memory pressure, so
    /// without them a history full of screenshots quietly holds every decoded
    /// thumbnail at once.
    static let thumbnails: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 120
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    static var directory: URL? {
        (ClipboardLibraryProbe.root ?? PrivateFileStore.containerURL)?
            .appendingPathComponent("ClipboardImages", isDirectory: true)
    }

    static func store(_ data: Data) -> String? {
        guard let directory else { return nil }
        PrivateFileStore.createDirectory(at: directory)
        let name = UUID().uuidString + ".png"
        guard PrivateFileStore.write(data, to: directory.appendingPathComponent(name)) else {
            return nil
        }
        return name
    }

    static func storeRepresentation(_ data: Data, type: String) -> String? {
        guard let directory else { return nil }
        PrivateFileStore.createDirectory(at: directory)
        let name = ClipboardLibraryArchive.checksum(data) + ".payload"
        let url = directory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) { return name }
        return PrivateFileStore.write(data, to: url) ? name : nil
    }

    static func imageData(named name: String) -> Data? {
        guard let directory, let url = try? ClipboardLibraryArchive.safeAsset(name, in: directory) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Downsampled preview for list rows, cached; loading full PNGs per row
    /// would drag the quick window.
    static func thumbnail(named name: String) -> NSImage? {
        if let cached = thumbnails.object(forKey: name as NSString) {
            return cached
        }
        guard let directory else { return nil }
        let url = directory.appendingPathComponent(name)
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 480,
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options)
        else { return nil }
        let image = NSImage(cgImage: cgImage, size: .zero)
        thumbnails.setObject(image, forKey: name as NSString,
                             cost: cgImage.bytesPerRow * cgImage.height)
        return image
    }

    /// Where a list thumbnail comes from; also its identity for a row that
    /// loads it asynchronously.
    enum ThumbnailSource: Hashable {
        case stored(name: String)
        case file(path: String, maxPixelSize: CGFloat = 480)
    }

    static func cachedThumbnail(_ source: ThumbnailSource) -> NSImage? {
        switch source {
        case .stored(let name):
            return thumbnails.object(forKey: name as NSString)
        case .file(let path, let maxPixelSize):
            return thumbnails.object(forKey: fileThumbnailKey(path: path, maxPixelSize: maxPixelSize))
        }
    }

    /// The same downsample as the synchronous lookups, off the main thread.
    /// A screenshot PNG takes tens of milliseconds to decode, and once the
    /// history held more screenshots than the cache fits, rows that decoded
    /// while drawing redid it on every search keystroke and froze the field.
    /// A row that is filtered out or scrolled away before its turn cancels
    /// its decode instead of queueing work nobody will see.
    static func loadThumbnail(_ source: ThumbnailSource) async -> NSImage? {
        if let cached = cachedThumbnail(source) { return cached }
        let request = ThumbnailRequest()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                thumbnailQueue.addOperation {
                    guard !request.isCancelled else {
                        continuation.resume(returning: nil)
                        return
                    }
                    switch source {
                    case .stored(let name):
                        continuation.resume(returning: thumbnail(named: name))
                    case .file(let path, let maxPixelSize):
                        continuation.resume(returning: fileThumbnail(atPath: path, maxPixelSize: maxPixelSize))
                    }
                }
            }
        } onCancel: {
            request.cancel()
        }
    }

    /// Two decodes at a time: a burst of new rows should not hold dozens of
    /// full size screenshots in memory at once.
    static let thumbnailQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "io.github.xztyle.Aster.clipboard-thumbnails"
        queue.maxConcurrentOperationCount = 2
        queue.qualityOfService = .userInitiated
        return queue
    }()

    final class ThumbnailRequest: @unchecked Sendable {
        let lock = NSLock()
        var cancelled = false

        var isCancelled: Bool { lock.withLock { cancelled } }
        func cancel() { lock.withLock { cancelled = true } }
    }

    static func fileThumbnailKey(path: String, maxPixelSize: CGFloat) -> NSString {
        "file:\(path):\(Int(maxPixelSize))" as NSString
    }

    /// The Finder icon for a path, cached: the workspace lookup is a round
    /// trip, and a list row asks for it every time it is drawn.
    static func fileIcon(atPath path: String) -> NSImage {
        if let cached = fileIcons.object(forKey: path as NSString) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        fileIcons.setObject(icon, forKey: path as NSString)
        fileIconPaths = fileIconPaths.filter { fileIcons.object(forKey: $0 as NSString) != nil }
        fileIconPaths.insert(path)
        return icon
    }

    static var fileIconPaths: Set<String> = []
    static let fileIcons: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 120
        return cache
    }()

    static func isImageFile(atPath path: String) -> Bool {
        ClipboardHistoryImageSupport.isImageFilePath(path)
    }

    /// Downsampled preview for a copied image file on disk, cached.
    static func fileThumbnail(atPath path: String, maxPixelSize: CGFloat = 480) -> NSImage? {
        let key = fileThumbnailKey(path: path, maxPixelSize: maxPixelSize)
        if let cached = thumbnails.object(forKey: key) {
            return cached
        }
        guard isImageFile(atPath: path) else { return nil }
        let url = URL(fileURLWithPath: path)
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options)
        else { return nil }
        let image = NSImage(cgImage: cgImage, size: .zero)
        thumbnails.setObject(image, forKey: key,
                             cost: cgImage.bytesPerRow * cgImage.height)
        return image
    }

    static func imageDimensions(atPath path: String) -> (width: Int, height: Int)? {
        guard isImageFile(atPath: path) else { return nil }
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }
        guard let rawWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let rawHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              rawWidth > 0, rawHeight > 0
        else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        if (5...8).contains(orientation) {
            return (rawHeight, rawWidth)
        }
        return (rawWidth, rawHeight)
    }

    static func imageDimensionsLabel(atPath path: String) -> String? {
        guard let dim = imageDimensions(atPath: path) else { return nil }
        return "\(dim.width)×\(dim.height)"
    }

    static func fileSizeString(atPath path: String) -> String? {
        guard let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.fileSizeKey]),
              let bytes = values.fileSize, bytes >= 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    static func cleanup(keeping names: Set<String>, filePaths: Set<String>) {
        for path in fileIconPaths where !filePaths.contains(path) {
            fileIcons.removeObject(forKey: path as NSString)
        }
        fileIconPaths.formIntersection(filePaths)
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(at: directory,
                                                                       includingPropertiesForKeys: nil)
        else { return }
        for file in files where !names.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
            thumbnails.removeObject(forKey: file.lastPathComponent as NSString)
        }
    }
}

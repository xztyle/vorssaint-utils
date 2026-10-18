// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import Foundation

struct StorageMapItem: Identifiable, Equatable {
    enum Kind { case folder, file, other }
    let id: String
    let url: URL?
    let bytes: Int64
    let kind: Kind
    var count = 1
}

struct StorageMapContent {
    var folders: [StorageFolderTotal] = []
    var files: [StorageFileSnapshot] = []
    var items: [StorageMapItem] = []

    static func make(result: StorageScanResult, roots: [URL], folder: URL?,
                     minimumBytes: Int64? = nil, modifiedBefore: Date? = nil) -> Self {
        let admitted = roots.filter { result.folders[$0.path] != nil }
        let top = admitted.filter { root in !admitted.contains { $0 != root && StorageInspectionPolicy.isWithin(root, root: $0) } }
        let folders = result.folders.values.filter { value in
            folder.map { parent in value.url.path != parent.path && value.url.deletingLastPathComponent().path == parent.path }
                ?? top.contains(where: { $0.path == value.url.path })
        }.sorted { $0.bytes == $1.bytes ? $0.id < $1.id : $0.bytes > $1.bytes }
        let files = result.files.filter { file in
            (folder != nil || minimumBytes != nil || modifiedBefore != nil)
                && (folder == nil || file.url.deletingLastPathComponent().path == folder?.path)
                && (minimumBytes.map { file.logicalBytes >= $0 } ?? true)
                && (modifiedBefore.map { cutoff in file.modified.map { $0 < cutoff } ?? false } ?? true)
        }.sorted { $0.allocatedBytes == $1.allocatedBytes ? $0.id < $1.id : $0.allocatedBytes > $1.allocatedBytes }
        var items = folders.map { StorageMapItem(id: $0.id, url: $0.url, bytes: $0.bytes, kind: .folder) }
        if folder != nil { items += files.map { StorageMapItem(id: $0.id, url: $0.url, bytes: $0.allocatedBytes, kind: .file) } }
        items.sort { $0.bytes == $1.bytes ? $0.id < $1.id : $0.bytes > $1.bytes }
        return Self(folders: folders, files: files, items: items)
    }

    var bubbles: [StorageMapItem] {
        let positive = items.filter { $0.bytes > 0 }
        guard positive.count > 16 else { return positive }
        let remainder = positive.dropFirst(15)
        let bytes = remainder.reduce(Int64(0)) { sum, item in
            let next = sum.addingReportingOverflow(item.bytes)
            return next.overflow ? Int64.max : next.partialValue
        }
        return Array(positive.prefix(15)) + [.init(id: "storage-map-other", url: nil, bytes: bytes, kind: .other, count: remainder.count)]
    }
}

struct StorageMapNavigation: Equatable {
    private var trail: [URL?] = [nil]
    private var index = 0
    var current: URL? { trail[index] }
    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index + 1 < trail.count }

    mutating func visit(_ folder: URL?) {
        guard current?.path != folder?.path else { return }
        trail = Array(trail.prefix(index + 1)) + [folder]
        index += 1
    }
    mutating func back() { if canGoBack { index -= 1 } }
    mutating func forward() { if canGoForward { index += 1 } }
    mutating func reset() { self = .init() }

    func breadcrumbs(roots: [URL]) -> [URL] {
        guard let current, let root = roots.filter({ StorageInspectionPolicy.isWithin(current, root: $0) })
            .min(by: { $0.pathComponents.count < $1.pathComponents.count }) else { return [] }
        var crumbs = [current]
        var parent = current
        while parent.path != root.path { parent.deleteLastPathComponent(); crumbs.append(parent) }
        return crumbs.reversed()
    }

    func parent(roots: [URL]) -> URL? {
        let crumbs = breadcrumbs(roots: roots)
        return crumbs.count > 1 ? crumbs[crumbs.count - 2] : nil
    }
}

struct StorageMapCircle: Identifiable {
    let id: String
    let center: CGPoint
    let radius: Double
}

/// Bounded packing keeps circle area proportional to allocated bytes. The
/// complete list retains tiny and zero-size files that cannot be hit in a map.
enum StorageMapLayout {
    static func circles(_ items: [StorageMapItem], size: CGSize) -> [StorageMapCircle] {
        guard size.width.isFinite, size.height.isFinite, size.width > 16, size.height > 16 else { return [] }
        let positive = Array(items.filter { $0.bytes > 0 }.prefix(16))
        guard let maximum = positive.map(\.bytes).max() else { return [] }
        let aspect = max(0.2, min(5, size.width / size.height))
        var placed: [StorageMapCircle] = []
        for item in positive {
            let radius = sqrt(Double(item.bytes) / Double(maximum))
            let center = position(radius: radius, placed: placed, aspect: aspect)
            placed.append(.init(id: item.id, center: center, radius: radius))
        }
        return fitted(placed, size: size)
    }

    private static func position(radius: Double, placed: [StorageMapCircle], aspect: Double) -> CGPoint {
        guard !placed.isEmpty else { return .zero }
        var best = CGPoint.zero
        var score = Double.infinity
        for neighbor in placed {
            for step in 0..<32 {
                let angle = Double(step) * .pi / 16
                let distance = neighbor.radius + radius + 0.025
                let center = CGPoint(x: neighbor.center.x + cos(angle) * distance, y: neighbor.center.y + sin(angle) * distance)
                guard placed.allSatisfy({ hypot(center.x - $0.center.x, center.y - $0.center.y) >= radius + $0.radius + 0.02 }) else { continue }
                let bounds = bounds(placed + [.init(id: "candidate", center: center, radius: radius)])
                let candidateScore = max(bounds.width / aspect, bounds.height)
                if candidateScore < score { score = candidateScore; best = center }
            }
        }
        return best
    }

    private static func bounds(_ circles: [StorageMapCircle]) -> CGRect {
        circles.reduce(CGRect.null) { rect, circle in
            rect.union(CGRect(x: circle.center.x - circle.radius, y: circle.center.y - circle.radius,
                              width: circle.radius * 2, height: circle.radius * 2))
        }
    }

    private static func fitted(_ circles: [StorageMapCircle], size: CGSize) -> [StorageMapCircle] {
        let bounds = bounds(circles)
        let scale = min((size.width - 16) / bounds.width, (size.height - 16) / bounds.height)
        return circles.map {
            .init(id: $0.id, center: CGPoint(x: size.width / 2 + ($0.center.x - bounds.midX) * scale,
                y: size.height / 2 + ($0.center.y - bounds.midY) * scale), radius: $0.radius * scale)
        }
    }
}

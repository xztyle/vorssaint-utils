// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Lifetime resets after interaction. Zero means keep open until explicitly closed.
enum ScreenshotPreviewLifetime: Int, CaseIterable {
    case keepOpen = 0, seconds15 = 15, seconds30 = 30, seconds60 = 60

    static func duration(_ value: Int) -> TimeInterval {
        TimeInterval((Self(rawValue: value) ?? .seconds30).rawValue)
    }
}

enum ScreenshotPreviewPolicy {
    static let maximumItems = 6
    static let maximumBytes = 256 * 1024 * 1024

    static func stackFrame(base: CGRect, visible: CGRect, index: Int,
                           top: Bool, right: Bool) -> CGRect {
        let gap: CGFloat = 12
        let rows = max(1, Int((visible.height - gap) / (base.height + gap)))
        let column = index / rows
        let row = index % rows
        let dx = CGFloat(column) * (base.width + gap) * (right ? -1 : 1)
        let dy = CGFloat(row) * (base.height + gap) * (top ? -1 : 1)
        var frame = base.offsetBy(dx: dx, dy: dy)
        frame.origin.x = min(max(frame.minX, visible.minX + gap),
                             max(visible.minX + gap, visible.maxX - frame.width - gap))
        frame.origin.y = min(max(frame.minY, visible.minY + gap),
                             max(visible.minY + gap, visible.maxY - frame.height - gap))
        return frame
    }

    static func evictionCandidates(items: [(id: UUID, bytes: Int, active: Bool)]) -> [UUID] {
        var count = items.count
        var bytes = items.reduce(0) { $0 + $1.bytes }
        var result: [UUID] = []
        for item in items where !item.active {
            guard count > 1, count > maximumItems || bytes > maximumBytes else { break }
            result.append(item.id)
            count -= 1
            bytes -= item.bytes
        }
        return result
    }
}

/// The floating preview has no shell. Its only permanent pixels are the image.
extension ScreenshotPreviewPolicy {
    static func imageSize(_ image: CGSize) -> CGSize {
        guard image.width > 0, image.height > 0, image.width.isFinite, image.height.isFinite else {
            return CGSize(width: 1, height: 1)
        }
        let factor = min(320 / image.width, 210 / image.height, 1)
        return CGSize(width: image.width * factor, height: image.height * factor)
    }

    static func floatingSize(image: CGSize) -> CGSize {
        let size = imageSize(image)
        // Transparent hit space keeps hover controls usable for a very thin crop.
        return CGSize(width: max(116, size.width), height: max(44, size.height))
    }

    static func showsActions(hovered: Bool, menuTracking: Bool, dragging: Bool) -> Bool {
        !dragging && (hovered || menuTracking)
    }
}

/// A native drop always wins. Only an unaccepted, deliberate left-edge gesture
/// dismisses; a connected display on the left remains an ordinary drag route.
enum ScreenshotPreviewDismissGesture {
    static func shouldDismiss(start: CGPoint, end: CGPoint, sourceScreen: CGRect,
                              otherScreens: [CGRect], accepted: Bool, cancelled: Bool) -> Bool {
        guard !accepted, !cancelled, sourceScreen.width > 0, sourceScreen.height > 0,
              end.x <= sourceScreen.minX + 8, end.x >= sourceScreen.minX - 8,
              end.y >= sourceScreen.minY, end.y <= sourceScreen.maxY else { return false }
        let dx = end.x - start.x, dy = end.y - start.y
        guard dx <= -48, abs(dx) >= abs(dy) * 1.5 else { return false }
        let acrossEdge = CGPoint(x: sourceScreen.minX - 1, y: end.y)
        return !otherScreens.contains { $0.contains(acrossEdge) }
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import CoreGraphics

struct MenuBarMoveDestination {
    let windowID: CGWindowID
    let frame: CGRect
    let after: Bool
    var usesWindowRouting = false

    var point: CGPoint { MenuBarMoveGeometry.point(in: frame, after: after) }
}

enum MenuBarMoveGeometry {
    static func destination(before target: ManagedMenuBarItem, excluding source: MenuBarItemIdentity,
                            items: [ManagedMenuBarItem]) -> MenuBarMoveDestination {
        let ordered = MenuBarOrganizerSupport.orderedItems(items, in: target.section).filter { $0.id != source }
        if target.isProtected, let index = ordered.firstIndex(where: { $0.id == target.id }), index > 0 {
            let previous = ordered[index - 1]
            if previous.isProtected, previous.identityState == .stable,
               abs(previous.frame.minY - target.frame.minY) <= 1 {
                return .init(windowID: previous.windowID, frame: previous.frame, after: true)
            }
        }
        return .init(windowID: target.windowID, frame: target.frame, after: false)
    }

    static func isOnMenuRow(_ frame: CGRect, screens: [CGRect]) -> Bool {
        guard valid(frame) else { return false }
        return screens.contains { abs(frame.minY - $0.minY) <= 1
            && frame.minX >= $0.minX - 2 && frame.maxX <= $0.maxX + 2 }
    }

    static func hasSettled(_ frame: CGRect, previous: CGRect?, rowY: CGFloat) -> Bool {
        valid(frame) && abs(frame.minY - rowY) <= 1 && previous == frame
    }

    static func point(in frame: CGRect, after: Bool, topEdge: Bool = false) -> CGPoint {
        let inset = topEdge ? min(CGFloat(1), frame.width / 4) : frame.width / 4
        return CGPoint(x: after ? frame.maxX - inset : frame.minX + inset,
                       y: topEdge ? frame.minY : frame.midY)
    }

    static func pressPoint(in frame: CGRect) -> CGPoint {
        CGPoint(x: frame.midX, y: frame.midY)
    }

    static func dragRegion(from start: CGPoint, to end: CGPoint, regions: [CGRect]) -> CGRect? {
        guard [start.x, start.y, end.x, end.y].allSatisfy(\.isFinite),
              abs(start.y - end.y) <= 1 else { return nil }
        return regions.first { $0.contains(start) && $0.contains(end) }
    }

    private static func valid(_ frame: CGRect) -> Bool {
        [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite)
            && frame.width > 0 && frame.height > 0
    }

    // MARK: - macOS 27 visible reorder

    /// Immediately left of the target. Neighbouring frames can overlap by a
    /// few points, so order uses centres and no other icon may sit between.
    static func isBefore(_ source: CGRect, _ target: CGRect, among frames: [CGRect]) -> Bool {
        source.midX < target.midX && !frames.contains { $0.midX > source.midX && $0.midX < target.midX }
    }

    /// Release over the target's leading part. Dragging rightward, the target
    /// slides left by the source's width once the source leaves its slot.
    /// Later attempts nudge the release point further toward the leading edge.
    static func dropX(source: CGRect, target: CGRect, attempt: Int) -> CGFloat {
        let shift = source.midX < target.midX ? source.width : 0
        let inset = max(2, target.width * (0.3 - 0.1 * CGFloat(attempt)))
        return target.minX - shift + inset
    }

    static func dragRow(_ source: CGRect, _ target: CGRect) -> CGRect {
        let minX = min(source.minX, target.minX - source.width) - 4
        let maxX = max(source.maxX, target.maxX) + 4
        return CGRect(x: minX, y: source.minY - 2, width: maxX - minX, height: source.height + 4)
    }
}

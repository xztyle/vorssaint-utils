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
}

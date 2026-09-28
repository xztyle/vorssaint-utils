// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation

enum MenuBarMoveGeometry {
    static func isOnMenuRow(_ frame: CGRect, screens: [CGRect]) -> Bool {
        guard valid(frame) else { return false }
        return screens.contains { abs(frame.minY - $0.minY) <= 1
            && frame.minX >= $0.minX - 2 && frame.maxX <= $0.maxX + 2 }
    }

    static func hasSettled(_ frame: CGRect, previous: CGRect?, rowY: CGFloat) -> Bool {
        valid(frame) && abs(frame.minY - rowY) <= 1 && previous == frame
    }

    static func point(in frame: CGRect, after: Bool) -> CGPoint {
        CGPoint(x: after ? frame.maxX + 1 : frame.minX - 1, y: frame.minY)
    }

    private static func valid(_ frame: CGRect) -> Bool {
        [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite)
            && frame.width > 0 && frame.height > 0
    }
}

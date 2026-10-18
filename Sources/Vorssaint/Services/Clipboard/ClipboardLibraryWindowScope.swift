// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import AppKit

/// The card preview belongs to the drawer even though AppKit gives it another
/// window. Other Aster windows must still count as outside clicks.
struct ClipboardLibraryWindowScope {
    let drawer: NSWindow
    let preview: NSWindow?

    func owns(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        return window === drawer || window === preview
    }

    func owns(windowNumber: Int) -> Bool {
        guard windowNumber > 0 else { return false }
        return windowNumber == drawer.windowNumber || windowNumber == preview?.windowNumber
    }

    func contains(_ point: NSPoint) -> Bool {
        [drawer, preview].compactMap { $0 }.contains {
            $0.isVisible && $0.frame.insetBy(dx: -2, dy: -2).contains(point)
        }
    }
}

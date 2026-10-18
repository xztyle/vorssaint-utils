// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import AppKit

enum ClipboardDrawerSizingTests {
    static func run(_ suite: TestSuite) {
        let screen = NSRect(x: -1440, y: -900, width: 1440, height: 900)
        for (requested, expected) in [(310.0, 310.0), (100.0, 280.0), (1200.0, 630.0)] {
            let frame = ClipboardHistoryWindowSizing.frame(on: screen, preferredHeight: requested)
            suite.expect(frame == NSRect(x: -1440, y: -900, width: 1440, height: expected),
                         "resizing keeps the bottom and display edges fixed and limits the height")
        }
        let automatic = ClipboardHistoryWindowSizing.frame(on: screen)
        for invalid in [Double.nan, .infinity, -.infinity, 0, -100] {
            suite.expect(ClipboardHistoryWindowSizing.frame(on: screen, preferredHeight: invalid) == automatic,
                         "invalid saved heights recover to the automatic drawer size")
        }
        let small = NSRect(x: 0, y: 0, width: 640, height: 240)
        suite.expect(ClipboardHistoryWindowSizing.frame(on: small, preferredHeight: 600) == small,
                     "a restored height cannot overflow a smaller display")
        for language in AppLanguage.allCases {
            suite.expect(!ClipboardLibraryStrings(language: language).resizeHeight.isEmpty,
                         "the invisible resize edge has a localized accessibility label")
        }
    }
}

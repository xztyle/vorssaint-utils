// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

extension DefaultsKey {
    static let screenshotCaptureMenuShortcutEnabled = "screenshotCaptureMenuShortcutEnabled"
    static let screenshotCaptureMenuShortcut = "screenshotCaptureMenuShortcut"
    static let screenshotAreaClipboardShortcutEnabled = "screenshotAreaClipboardShortcutEnabled"
    static let screenshotAreaClipboardShortcut = "screenshotAreaClipboardShortcut"
    static let screenshotFullScreenClipboardShortcutEnabled = "screenshotFullScreenClipboardShortcutEnabled"
    static let screenshotFullScreenClipboardShortcut = "screenshotFullScreenClipboardShortcut"
}

enum ScreenshotShortcutLabels {
    static func areaToClipboard(_ language: AppLanguage) -> String {
        let strings = FeatureStrings.screenshot(language)
        return strings.hintDrag + " · " + strings.copyButton
    }

    static func fullScreenToClipboard(_ language: AppLanguage) -> String {
        let strings = FeatureStrings.screenshot(language)
        return strings.fullScreenShortcutTitle + " · " + strings.copyButton
    }
}

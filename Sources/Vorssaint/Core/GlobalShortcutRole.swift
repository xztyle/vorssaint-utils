// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum GlobalShortcutRole: CaseIterable, Identifiable {
    case keepAwake
    case shelf
    case switcher
    case switcherWindow
    case clipboard
    case soundOutputSwitcher
    case pastePlain
    case finderRename
    case colorPicker
    case screenOCR
    case micMute
    case quickLauncher
    case screenshot
    case screenshotFullScreen
    case screenshotLastCapture
    case recentCaptures
    case screenshotClipboard
    case cameraPreview
    case radialMenu
    case scratchpad
    case snippetLibrary
    case menuBarReveal, menuBarAlways, menuBarPanel, menuBarSearch, menuBarProfile
    case commandBar
    case screenRecorder
    case displayBrightnessDecrease
    case displayBrightnessIncrease
    case keyboardBrightnessDecrease
    case keyboardBrightnessIncrease
    case pointerNextDisplay

    static let menuBarRoles: [Self] = [.menuBarReveal, .menuBarAlways, .menuBarPanel, .menuBarSearch, .menuBarProfile]

    var id: String { storageKey }

    var storageKey: String {
        switch self {
        case .keepAwake: return DefaultsKey.keepAwakeShortcut
        case .shelf: return DefaultsKey.shelfShortcut
        case .switcher: return DefaultsKey.switcherShortcut
        case .switcherWindow: return DefaultsKey.switcherWindowShortcut
        case .clipboard: return DefaultsKey.clipboardHistoryShortcut
        case .soundOutputSwitcher: return DefaultsKey.soundOutputSwitcherShortcut
        case .pastePlain: return DefaultsKey.pastePlainShortcut
        case .finderRename: return DefaultsKey.finderRenameShortcut
        case .colorPicker: return DefaultsKey.colorPickerShortcut
        case .screenOCR: return DefaultsKey.screenOCRShortcut
        case .micMute: return DefaultsKey.micMuteShortcut
        case .quickLauncher: return DefaultsKey.quickLauncherShortcut
        case .screenshot: return DefaultsKey.screenshotShortcut
        case .screenshotFullScreen: return DefaultsKey.screenshotFullScreenShortcut
        case .screenshotLastCapture: return DefaultsKey.screenshotLastCaptureShortcut
        case .recentCaptures: return DefaultsKey.recentCapturesShortcut
        case .screenshotClipboard: return DefaultsKey.screenshotClipboardShortcut
        case .cameraPreview: return DefaultsKey.cameraPreviewShortcut
        case .radialMenu: return DefaultsKey.radialMenuShortcut
        case .scratchpad: return DefaultsKey.scratchpadShortcut
        case .snippetLibrary: return DefaultsKey.snippetLibraryShortcut
        case .menuBarReveal: return DefaultsKey.menuBarOrganizerRevealShortcut
        case .menuBarAlways: return DefaultsKey.menuBarOrganizerAlwaysShortcut
        case .menuBarPanel: return DefaultsKey.menuBarOrganizerPanelShortcut
        case .menuBarSearch: return DefaultsKey.menuBarOrganizerSearchShortcut
        case .menuBarProfile: return DefaultsKey.menuBarOrganizerProfileShortcut
        case .commandBar: return DefaultsKey.commandBarShortcut
        case .screenRecorder: return DefaultsKey.recorderShortcut
        case .displayBrightnessDecrease: return DefaultsKey.displayBrightnessDecreaseShortcut
        case .displayBrightnessIncrease: return DefaultsKey.displayBrightnessIncreaseShortcut
        case .keyboardBrightnessDecrease: return DefaultsKey.keyboardBrightnessDecreaseShortcut
        case .keyboardBrightnessIncrease: return DefaultsKey.keyboardBrightnessIncreaseShortcut
        case .pointerNextDisplay: return DefaultsKey.pointerDisplayShortcut
        }
    }

    var defaultShortcut: GlobalShortcut {
        switch self {
        case .keepAwake: return .keepAwakeDefault
        case .shelf: return .shelfDefault
        case .switcher: return .switcherDefault
        case .switcherWindow: return .switcherWindowDefault
        case .clipboard: return .clipboardDefault
        case .soundOutputSwitcher: return .soundOutputSwitcherDefault
        case .pastePlain: return .pastePlainDefault
        case .finderRename: return .finderRenameDefault
        case .colorPicker: return .colorPickerDefault
        case .screenOCR: return .screenOCRDefault
        case .micMute: return .micMuteDefault
        case .quickLauncher: return .quickLauncherDefault
        case .screenshot: return .screenshotDefault
        case .screenshotFullScreen: return .screenshotFullScreenDefault
        case .screenshotLastCapture: return .screenshotLastCaptureDefault
        case .recentCaptures: return .recentCapturesDefault
        case .screenshotClipboard: return .screenshotClipboardDefault
        case .cameraPreview: return .cameraPreviewDefault
        case .radialMenu: return .radialMenuDefault
        case .scratchpad: return .scratchpadDefault
        case .snippetLibrary: return .snippetLibraryDefault
        case .menuBarReveal: return GlobalShortcut(storageValue: MenuBarOrganizerDefaults.values[storageKey] as! String)!
        case .menuBarAlways: return GlobalShortcut(storageValue: MenuBarOrganizerDefaults.values[storageKey] as! String)!
        case .menuBarPanel: return GlobalShortcut(storageValue: MenuBarOrganizerDefaults.values[storageKey] as! String)!
        case .menuBarSearch: return GlobalShortcut(storageValue: MenuBarOrganizerDefaults.values[storageKey] as! String)!
        case .menuBarProfile: return GlobalShortcut(storageValue: MenuBarOrganizerDefaults.values[storageKey] as! String)!
        case .commandBar: return .commandBarDefault
        case .screenRecorder: return .screenRecorderDefault
        case .displayBrightnessDecrease: return .displayBrightnessDecreaseDefault
        case .displayBrightnessIncrease: return .displayBrightnessIncreaseDefault
        case .keyboardBrightnessDecrease: return .keyboardBrightnessDecreaseDefault
        case .keyboardBrightnessIncrease: return .keyboardBrightnessIncreaseDefault
        case .pointerNextDisplay: return .pointerNextDisplayDefault
        }
    }

    var savedShortcut: GlobalShortcut {
        GlobalShortcut.saved(for: storageKey, fallback: defaultShortcut)
    }

    /// The switcher's event tap can handle its native combinations without
    /// changing the system takeover setting. Other system actions stay reserved.
    var permittedSystemShortcutIDs: Set<Int32> {
        switch self {
        case .switcher:
            return [SwitcherNativeSymbolicHotKey.commandTab.rawValue,
                    SwitcherNativeSymbolicHotKey.commandShiftTab.rawValue]
        case .switcherWindow:
            return [SwitcherNativeSymbolicHotKey.nextWindow.rawValue,
                    SwitcherNativeSymbolicHotKey.previousWindow.rawValue]
        default:
            return []
        }
    }

    func title(_ strings: Strings) -> String {
        switch self {
        case .keepAwake: return strings.keepAwakeTitle
        case .shelf: return strings.shelfName
        case .switcher: return strings.switcherSection
        case .switcherWindow: return strings.switcherShortcutHintWindows
        case .clipboard: return FeatureStrings.clipboard(L10n.shared.language).title
        case .soundOutputSwitcher: return strings.soundOutputSwitcherTitle
        case .pastePlain: return strings.pastePlainName
        case .finderRename: return FeatureStrings.finderRename(L10n.shared.language).hubTitle
        case .colorPicker: return strings.colorPickerName
        case .screenOCR: return strings.ocrName
        case .micMute: return strings.micMuteName
        case .quickLauncher: return strings.launcherName
        case .screenshot:
            return FeatureStrings.screenshot(L10n.shared.language).pageTitle
        case .screenshotFullScreen:
            return FeatureStrings.screenshot(L10n.shared.language).fullScreenShortcutTitle
        case .screenshotLastCapture:
            return FeatureStrings.screenshot(L10n.shared.language).editLastCapture
        case .recentCaptures:
            return FeatureStrings.recentCaptures(L10n.shared.language).title
        case .screenshotClipboard:
            return FeatureStrings.screenshot(L10n.shared.language).editClipboardImage
        case .cameraPreview: return FeatureStrings.cameraPreview(L10n.shared.language).pageTitle
        case .radialMenu: return FeatureStrings.radialMenu(L10n.shared.language).pageTitle
        case .scratchpad: return FeatureStrings.scratchpad(L10n.shared.language).pageTitle
        case .snippetLibrary: return FeatureStrings.snippets(L10n.shared.language).libraryTitle
        case .menuBarReveal: return MenuBarProductStrings.localized(L10n.shared.language).shortcutReveal
        case .menuBarAlways: return MenuBarProductStrings.localized(L10n.shared.language).shortcutAlways
        case .menuBarPanel: return MenuBarProductStrings.localized(L10n.shared.language).shortcutPanel
        case .menuBarSearch: return MenuBarProductStrings.localized(L10n.shared.language).shortcutSearch
        case .menuBarProfile: return MenuBarProductStrings.localized(L10n.shared.language).shortcutProfile
        case .commandBar: return FeatureStrings.commandBar(L10n.shared.language).pageTitle
        case .screenRecorder: return FeatureStrings.recorder(L10n.shared.language).pageTitle
        case .displayBrightnessDecrease:
            return FeatureStrings.brightness(L10n.shared.language).displayBrightnessDecrease
        case .displayBrightnessIncrease:
            return FeatureStrings.brightness(L10n.shared.language).displayBrightnessIncrease
        case .keyboardBrightnessDecrease:
            return FeatureStrings.brightness(L10n.shared.language).keyboardBrightnessDecrease
        case .keyboardBrightnessIncrease:
            return FeatureStrings.brightness(L10n.shared.language).keyboardBrightnessIncrease
        case .pointerNextDisplay: return PointerDisplayStrings.localized(L10n.shared.language).title
        }
    }

    static func conflict(for shortcut: GlobalShortcut,
                         excluding role: GlobalShortcutRole?,
                         isOn: (String) -> Bool = { UserDefaults.standard.bool(forKey: $0) },
                         isAvailable: (AppFeature) -> Bool = { $0.isAvailable },
                         includeInactive: Bool = false) -> GlobalShortcutRole? {
        let candidates = includeInactive
            ? availableRoles(isAvailable: isAvailable)
            : activeRoles(isOn: isOn, isAvailable: isAvailable)
        return candidates.first { candidate in
            candidate != role && candidate.savedShortcut == shortcut
        }
    }

    /// The defaults keys that must ALL be true for this role's shortcut to be
    /// registered. Some shortcuts gate on their own toggle, some follow the
    /// feature switch, and the clipboard needs both the feature and its
    /// shortcut toggle.
    var requiredEnableKeys: [String] {
        switch self {
        case .keepAwake: return [DefaultsKey.hotkeyEnabled]
        case .shelf: return [DefaultsKey.shelfEnabled, DefaultsKey.shelfShortcutEnabled]
        case .switcher, .switcherWindow: return [DefaultsKey.switcherEnabled]
        case .clipboard: return [DefaultsKey.clipboardHistoryEnabled,
                                 DefaultsKey.clipboardHistoryShortcutEnabled]
        case .soundOutputSwitcher: return [DefaultsKey.soundOutputSwitcherEnabled]
        case .pastePlain: return [DefaultsKey.pastePlainEnabled]
        case .finderRename: return [DefaultsKey.finderRenameEnabled]
        case .colorPicker: return [DefaultsKey.colorPickerShortcutEnabled]
        case .screenOCR: return [DefaultsKey.screenOCRShortcutEnabled]
        case .micMute: return [DefaultsKey.micMuteShortcutEnabled]
        case .quickLauncher: return [DefaultsKey.quickLauncherShortcutEnabled]
        case .screenshot: return [DefaultsKey.screenshotShortcutEnabled]
        case .screenshotFullScreen: return [DefaultsKey.screenshotFullScreenShortcutEnabled]
        case .screenshotLastCapture: return [DefaultsKey.screenshotLastCaptureShortcutEnabled]
        case .recentCaptures: return [DefaultsKey.recentCapturesShortcutEnabled]
        case .screenshotClipboard: return [DefaultsKey.screenshotClipboardShortcutEnabled]
        case .cameraPreview: return [DefaultsKey.cameraPreviewShortcutEnabled]
        case .radialMenu: return [DefaultsKey.radialMenuEnabled]
        case .scratchpad: return [DefaultsKey.scratchpadShortcutEnabled]
        case .snippetLibrary: return [DefaultsKey.snippetLibraryEnabled]
        case .menuBarReveal, .menuBarAlways, .menuBarPanel, .menuBarSearch, .menuBarProfile: return [DefaultsKey.menuBarOrganizerEnabled]
        case .commandBar: return [DefaultsKey.commandBarShortcutEnabled]
        case .screenRecorder: return [DefaultsKey.recorderShortcutEnabled]
        case .displayBrightnessDecrease, .displayBrightnessIncrease:
            return [DefaultsKey.brightnessControlEnabled, DefaultsKey.displayBrightnessShortcutsEnabled]
        case .keyboardBrightnessDecrease, .keyboardBrightnessIncrease:
            return [DefaultsKey.keyboardBrightnessShortcutsEnabled]
        case .pointerNextDisplay: return [DefaultsKey.pointerDisplayEnabled]
        }
    }

    /// The hub feature behind each shortcut; a feature switched off in the
    /// hub takes its shortcut off the overview page (the hotkey itself is
    /// already dead through the service's own availability guard).
    var feature: AppFeature {
        switch self {
        case .keepAwake: return .keepAwake
        case .shelf: return .shelf
        case .switcher, .switcherWindow: return .switcher
        case .clipboard: return .clipboardHistory
        case .soundOutputSwitcher: return .soundOutputSwitcher
        case .pastePlain: return .pastePlain
        case .finderRename: return .finderRename
        case .colorPicker: return .colorPicker
        case .screenOCR: return .screenOCR
        case .micMute: return .micMute
        case .quickLauncher: return .quickLauncher
        case .screenshot, .screenshotFullScreen, .screenshotLastCapture, .recentCaptures,
             .screenshotClipboard:
            return .screenshot
        case .cameraPreview: return .cameraPreview
        case .radialMenu: return .radialMenu
        case .scratchpad: return .scratchpad
        case .snippetLibrary: return .textSnippets
        case .menuBarReveal, .menuBarAlways, .menuBarPanel, .menuBarSearch, .menuBarProfile: return .menuBarOrganizer
        case .commandBar: return .commandBar
        case .screenRecorder: return .screenRecorder
        case .displayBrightnessDecrease, .displayBrightnessIncrease: return .brightness
        case .keyboardBrightnessDecrease, .keyboardBrightnessIncrease: return .brightness
        case .pointerNextDisplay: return .windowLayout
        }
    }

    /// Keyboard-backlight shortcuts belong with keyboard controls in the
    /// editor, while their implementation remains part of the brightness
    /// service and follows that feature's availability.
    var group: FeatureGroup {
        switch self {
        case .keyboardBrightnessDecrease, .keyboardBrightnessIncrease: return .mouseKeyboard
        default: return feature.group
        }
    }

    /// Whether a claim ever reaches `SystemShortcutTakeover` for this key, and
    /// so whether the recorder may offer to take a macOS shortcut over. The
    /// switcher suppresses its keys through its own take-over toggle rather
    /// than a claim, and the radial menu's role key is only a migration seed —
    /// the live shortcuts are the per-profile ones. A row that cannot keep the
    /// promise refuses the combination instead of making it.
    var supportsTakeOver: Bool {
        switch self {
        case .switcher, .switcherWindow, .radialMenu: return false
        default: return true
        }
    }

    var isKeyboardBrightness: Bool {
        self == .keyboardBrightnessDecrease || self == .keyboardBrightnessIncrease
    }

    /// Capture roles normally follow their own tool. Shared capture history
    /// stays available while either kind of capture that fills it is installed.
    var availabilityFeatures: [AppFeature] {
        switch self {
        case .recentCaptures: return [.screenshot, .screenRecorder]
        default: return [feature]
        }
    }

    func isAvailable(using isAvailable: (AppFeature) -> Bool) -> Bool {
        availabilityFeatures.contains(where: isAvailable)
    }

    /// The features whose own shortcuts have to go quiet while the user is
    /// recording a new one, or the combination being typed fires the feature
    /// instead of landing in the field. Derived from the roles, so a shortcut
    /// added later is covered the day its role is added. Re-registering is a
    /// plain `FeatureRuntime.sync` of this same list.
    static var featuresToSilenceWhileRecording: [AppFeature] {
        var seen: Set<AppFeature> = []
        var features = allCases.compactMap { seen.insert($0.feature).inserted ? $0.feature : nil }
        // Window layout keeps one shortcut per action instead of a role, so it
        // is the one holder of global keys the list above cannot reach.
        if seen.insert(.windowLayout).inserted { features.append(.windowLayout) }
        return features
    }

    /// Roles whose shortcut is live given a defaults reader, for the keyboard
    /// shortcuts overview page. Injected readers so the harness can test the
    /// gating without touching real defaults.
    static func activeRoles(isOn: (String) -> Bool,
                            isAvailable: (AppFeature) -> Bool = { _ in true }) -> [GlobalShortcutRole] {
        allCases.filter { role in
            role.isAvailable(using: isAvailable) && role.requiredEnableKeys.allSatisfy(isOn)
        }
    }

    /// Every shortcut belonging to an installed feature, including choices
    /// that are currently switched off but can still be edited and kept for
    /// later on the central shortcuts page.
    static func availableRoles(isAvailable: (AppFeature) -> Bool = { $0.isAvailable })
        -> [GlobalShortcutRole] {
        allCases.filter { $0.isAvailable(using: isAvailable) }
    }

    /// The features whose shortcuts share one Screen capture group on the
    /// central shortcuts page.
    static let captureFeatures: [AppFeature] =
        [.screenshot, .screenRecorder, .screenOCR, .colorPicker]

    /// Chooser tools first, in chooser order, then shared history and screenshot extras.
    static let captureDisplayOrder: [GlobalShortcutRole] = [
        .screenshot, .screenRecorder, .screenOCR, .colorPicker,
        .recentCaptures, .screenshotFullScreen, .screenshotLastCapture, .screenshotClipboard,
    ]

    /// The given roles narrowed to the capture group, in display order. The
    /// order list only sorts, so an unlisted role lands at the end instead of
    /// vanishing.
    static func captureRoles(in roles: [GlobalShortcutRole]) -> [GlobalShortcutRole] {
        roles.filter { captureFeatures.contains($0.feature) }
            .enumerated()
            .sorted { lhs, rhs in
                (captureDisplayOrder.firstIndex(of: lhs.element) ?? .max, lhs.offset)
                    < (captureDisplayOrder.firstIndex(of: rhs.element) ?? .max, rhs.offset)
            }
            .map(\.element)
    }
}


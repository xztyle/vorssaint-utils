// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation

extension DefaultsKey {
    static let menuBarOrganizerEnabled = "menuBarOrganizerEnabled"
    static let menuBarOrganizerSetupComplete = "menuBarOrganizerSetupComplete"
    static let menuBarOrganizerAlwaysHiddenEnabled = "menuBarOrganizerAlwaysHiddenEnabled"
    static let menuBarOrganizerShowDividers = "menuBarOrganizerShowDividers"
    static let menuBarOrganizerPresentationMode = "menuBarOrganizerPresentationMode"
    static let menuBarOrganizerLibrary = "menuBarOrganizerLibrary"
    static let menuBarOrganizerBaseline = "menuBarOrganizerBaseline"
    static let menuBarOrganizerLayout = "menuBarOrganizerLayout"
    static let menuBarOrganizerRevealShortcut = "menuBarOrganizerRevealShortcut"
    static let menuBarOrganizerAlwaysShortcut = "menuBarOrganizerAlwaysShortcut"
    static let menuBarOrganizerPanelShortcut = "menuBarOrganizerPanelShortcut"
    static let menuBarOrganizerSearchShortcut = "menuBarOrganizerSearchShortcut"
    static let menuBarOrganizerProfileShortcut = "menuBarOrganizerProfileShortcut"
}

enum MenuBarOrganizerDefaults {
    static let values: [String: Any] = [
        DefaultsKey.menuBarOrganizerEnabled: false,
        DefaultsKey.menuBarOrganizerSetupComplete: false,
        DefaultsKey.menuBarOrganizerAlwaysHiddenEnabled: true,
        DefaultsKey.menuBarOrganizerShowDividers: false,
        DefaultsKey.menuBarOrganizerPresentationMode: "automatic",
        DefaultsKey.menuBarOrganizerLibrary: Data(),
        DefaultsKey.menuBarOrganizerLayout: Data(),
        DefaultsKey.menuBarOrganizerRevealShortcut: "control+option+command:11",
        DefaultsKey.menuBarOrganizerAlwaysShortcut: "control+option+shift+command:11",
        DefaultsKey.menuBarOrganizerPanelShortcut: "control+option+command:0",
        DefaultsKey.menuBarOrganizerSearchShortcut: "control+option+command:3",
        DefaultsKey.menuBarOrganizerProfileShortcut: "control+option+shift+command:0",
    ]
}

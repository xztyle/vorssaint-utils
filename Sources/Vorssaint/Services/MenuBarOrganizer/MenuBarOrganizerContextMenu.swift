// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import AppKit

@MainActor
extension MenuBarOrganizerService {
    func showContextMenu() {
        guard let controlItem, let button = controlItem.statusItem.button else { return }
        let menu = NSMenu()
        let rows: [(String, Selector)] = [
            (extra.search, #selector(contextSearch)),
            (hiddenSectionShown ? text.contextHideHidden : text.contextShowHidden, #selector(contextHidden)),
            (alwaysHiddenSectionShown ? text.contextHideAlways : text.contextShowAlways, #selector(contextAlways)),
            (text.secondaryBar, #selector(contextPanel)),
            (text.contextSettings, #selector(contextSettings)),
            (text.contextDisable, #selector(contextDisable)),
        ]
        for row in rows {
            let item = menu.addItem(withTitle: row.0, action: row.1, keyEquivalent: "")
            item.target = self
        }
        controlItem.statusItem.menu = menu
        button.performClick(nil)
        DispatchQueue.main.async { controlItem.statusItem.menu = nil }
    }

    @objc func contextSearch() { showSearch() }
    @objc func contextHidden() { toggleHiddenSection() }
    @objc func contextAlways() { toggleAlwaysHiddenSection() }
    @objc func contextPanel() { showSecondaryBar() }
    @objc func contextSettings() {
        SettingsRouter.shared.page = .menuBarOrganizer
        (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
    }
    @objc func contextDisable() {
        UserDefaults.standard.set(false, forKey: DefaultsKey.menuBarOrganizerEnabled)
        syncWithPreferences()
    }
}

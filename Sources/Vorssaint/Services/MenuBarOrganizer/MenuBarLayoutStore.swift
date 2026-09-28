// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation

struct MenuBarLayoutStore {
    let defaults: UserDefaults

    func library() throws -> MenuBarLibrary {
        guard let data = defaults.data(forKey: DefaultsKey.menuBarOrganizerLibrary), !data.isEmpty
        else { return MenuBarLibrary() }
        let result = try JSONDecoder().decode(MenuBarLibrary.self, from: data)
        guard result.isValid else { throw CocoaError(.coderReadCorrupt) }
        return result
    }

    func save(_ library: MenuBarLibrary) throws {
        guard library.isValid else { throw CocoaError(.coderInvalidValue) }
        defaults.set(try JSONEncoder().encode(library), forKey: DefaultsKey.menuBarOrganizerLibrary)
    }

    func layout(for key: String) throws -> MenuBarLayout? {
        guard let data = defaults.data(forKey: key), !data.isEmpty else { return nil }
        let layout = try JSONDecoder().decode(MenuBarLayout.self, from: data)
        guard layout.isValid else { throw CocoaError(.coderReadCorrupt) }
        return layout
    }

    func save(_ layout: MenuBarLayout, for key: String) throws {
        guard layout.isValid else { throw CocoaError(.coderInvalidValue) }
        defaults.set(try JSONEncoder().encode(layout), forKey: key)
    }
}

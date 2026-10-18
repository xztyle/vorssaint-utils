// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import Foundation
import CoreFoundation

/// Uses the exact already-granted file domain so cfprefsd delivers the change
/// to MenuBarAgent. A raw file replacement alone leaves its cached order stale.
enum MenuBarNativePreferenceStore {
    static func read(at url: URL) throws -> [String: Any] {
        let domain = url.deletingPathExtension().path as CFString
        guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost),
              let root = CFPreferencesCopyMultiple(nil, domain, kCFPreferencesCurrentUser,
                  kCFPreferencesAnyHost) as? [String: Any] else { throw CocoaError(.fileReadNoPermission) }
        return root
    }

    static func write(_ updated: MenuBarNativeLayoutDocument, basedOn snapshot: MenuBarNativeLayoutDocument,
                      at url: URL) throws -> Data {
        guard equal(try read(at: url), snapshot.root),
              equal(untouched(updated.root), untouched(snapshot.root)) else { throw CocoaError(.fileWriteUnknown) }
        let domain = url.deletingPathExtension().path as CFString
        let positions = updated.root[MenuBarNativeLayoutDocument.positionsKey] as! [String: Any]
        CFPreferencesSetValue(MenuBarNativeLayoutDocument.positionsKey as CFString,
            positions as CFDictionary, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let result = try MenuBarNativeLayoutDocument(data: Data(contentsOf: url))
        guard equal(result.root, updated.root) else { throw CocoaError(.fileWriteUnknown) }
        return result.data
    }

    static func equal(_ first: [String: Any], _ second: [String: Any]) -> Bool {
        NSDictionary(dictionary: first).isEqual(to: second)
    }

    private static func untouched(_ root: [String: Any]) -> [String: Any] {
        root.filter { $0.key != MenuBarNativeLayoutDocument.positionsKey }
    }
}

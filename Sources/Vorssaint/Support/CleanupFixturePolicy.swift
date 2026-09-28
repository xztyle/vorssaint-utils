// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Fixture setup never turns an arbitrary existing folder into test data.
enum CleanupFixturePolicy {
    static func marker(_ root: URL) -> Data {
        Data(("Aster cleanup fixture 1\n" + root.path + "\n").utf8)
    }

    static func needsPreparation(_ root: URL) throws -> Bool {
        guard !UninstallerSupport.isSymbolicLink(root) else { throw StorageInspectionFailure.excluded }
        guard FileManager.default.fileExists(atPath: root.path) else { return true }
        let canonical = try StorageLocalAccess.canonicalRoot(root)
        let markerURL = canonical.appendingPathComponent("fixture.prepared")
        if !UninstallerSupport.isSymbolicLink(markerURL), let handle = try? FileHandle(forReadingFrom: markerURL) {
            defer { try? handle.close() }
            if let data = try? handle.read(upToCount: 4096), data == marker(canonical) { return false }
        }
        guard let iterator = FileManager.default.enumerator(atPath: canonical.path), iterator.nextObject() == nil else {
            throw StorageInspectionFailure.excluded
        }
        return true
    }
}

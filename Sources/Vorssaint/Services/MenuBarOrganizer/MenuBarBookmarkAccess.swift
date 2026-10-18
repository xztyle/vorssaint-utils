// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import Foundation

enum MenuBarBookmarkAccess {
    /// Renew only an already granted, successfully used scope for this exact
    /// file. A replaced plist is expected; a different resolved path is refused.
    static func perform<T>(bookmark: Data, expected: URL, renew: (Data) -> Void,
                           action: (URL) throws -> T) throws -> T {
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI, .withoutMounting],
                          relativeTo: nil, bookmarkDataIsStale: &stale)
        guard url.standardizedFileURL == expected.standardizedFileURL else { throw CocoaError(.fileReadNoPermission) }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let result = try action(url)
        if stale { renew(try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)) }
        return result
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum ClipboardFileDragPayload {
    static func urls(paths: [String]) -> [URL]? {
        guard !paths.isEmpty else { return nil }
        let urls = paths.map { URL(fileURLWithPath: $0) }
        guard urls.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else { return nil }
        return urls
    }
}

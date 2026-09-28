// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

struct ClipboardFileDragTests {
    static func run(_ suite: TestSuite) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AsterClipboardDragTests-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let paths = ["first.txt", "second.txt"].map { directory.appendingPathComponent($0).path }
        for path in paths { FileManager.default.createFile(atPath: path, contents: Data(path.utf8)) }

        guard let urls = ClipboardFileDragPayload.urls(paths: paths) else {
            suite.expect(false, "all generated files are available for drag")
            return
        }
        let board = NSPasteboard(name: NSPasteboard.Name("Aster.Tests.ClipboardDrag.\(UUID())"))
        board.clearContents()
        suite.expect(board.writeObjects(urls.map { $0 as NSURL }), "native drag writes every file URL")
        let received = (board.readObjects(forClasses: [NSURL.self], options: nil) as? [NSURL])?.compactMap(\.path)
        suite.expect(received == paths, "native file drag preserves every URL in order")

        try? FileManager.default.removeItem(atPath: paths[1])
        suite.expect(ClipboardFileDragPayload.urls(paths: paths) == nil,
                     "a missing file aborts the whole drag instead of dropping a partial group")
    }
}

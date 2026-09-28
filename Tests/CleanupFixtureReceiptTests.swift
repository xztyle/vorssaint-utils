// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum CleanupFixtureReceiptTests {
    static func run(_ suite: TestSuite) {
        let root = URL(fileURLWithPath: "/private/tmp/AsterGeneratedReceipt/Files")
        let first = file(root.appendingPathComponent("First.txt"), root: root)
        let second = file(root.appendingPathComponent("Second.txt"), root: root)
        let foreign = file(URL(fileURLWithPath: "/private/tmp/AsterGeneratedReceipt/Files-other/Private.txt"), root: root)
        let trash = URL(fileURLWithPath: "/fixture-trash/First.txt")
        let scan = StorageScanResult(files: [first, second, foreign])
        let duplicates = StorageDuplicateResult(groups: [
            .init(files: [first, second], keeperID: second.id), .init(files: [first, foreign], keeperID: nil)])
        let receipts: [StorageTrashReceipt] = [.init(original: first.url, trash: trash, failure: nil),
            .init(original: foreign.url, trash: URL(fileURLWithPath: "/private/other-trash"), failure: nil),
            .init(original: second.url, trash: nil, failure: "private diagnostic /foreign/file")]
        do {
            let data = try CleanupFixtureReceipt.data(root: root, scan: scan, duplicates: duplicates,
                receipts: receipts, selection: [first.id, foreign.id],
                malware: .init(findings: [.init(path: foreign.id, signature: "private detail")], scanned: 2), busy: false)
            let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            check(suite, state: object, text: String(decoding: data, as: UTF8.self), first: first, second: second, trash: trash)
        } catch { suite.expect(false, "fixture receipt encoding: \(error)") }
    }

    private static func check(_ suite: TestSuite, state: [String: Any], text: String,
                              first: StorageFileSnapshot, second: StorageFileSnapshot, trash: URL) {
        suite.expect(state["files"] as? [String] == [first.id, second.id]
            && state["selected"] as? [String] == [first.id], "fixture receipts retain only generated paths and selections")
        let groups = state["duplicates"] as? [[String: Any]]
        suite.expect(groups?.count == 1 && groups?.first?["keeper"] as? String == second.id,
                     "fixture receipts record the selected keeper and reject groups containing outside paths")
        let receipts = state["receipts"] as? [[String: Any]]
        suite.expect(receipts?.count == 2 && receipts?.first?["trash"] as? String == trash.path,
                     "fixture receipt preserves the real returned Trash URL for its generated original")
        suite.expect(!text.contains("Files-other") && !text.contains("private detail")
            && !text.contains("private diagnostic") && !text.contains("other-trash"),
                     "fixture receipt excludes outside paths and diagnostic or finding content")
        let malware = state["malware"] as? [String: Any]
        suite.expect(malware?["scanned"] as? Int == 2 && malware?["findings"] as? Int == 1,
                     "fixture receipt records malware outcome counts without path or signature content")
    }

    private static func file(_ url: URL, root: URL) -> StorageFileSnapshot {
        .init(url: url, root: root, identity: .init(device: 1, inode: 2), logicalBytes: 1,
              allocatedBytes: 1, modifiedSeconds: 1, modifiedNanoseconds: 0, ancestors: [])
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Serializes generated-only acceptance results. Called only by CleanupProbe;
/// it reads no file contents and records no paths outside the supplied scope,
/// except the actual returned Trash URL for a generated file in that scope.
enum CleanupFixtureReceipt {
    static func data(root: URL, scan: StorageScanResult, duplicates: StorageDuplicateResult,
                     receipts: [StorageTrashReceipt], selection: Set<String>,
                     malware: ClamAVScanResult?, busy: Bool) throws -> Data {
        var state: [String: Any] = [
            "schema": 1, "busy": busy,
            "files": scan.files.filter { within($0.url, root) }.map(\.id),
            "scanPartial": scan.isPartial,
            "selected": selection.filter { within(URL(fileURLWithPath: $0), root) }.sorted(),
            "duplicates": duplicateGroups(duplicates.groups, root: root),
            "duplicatesIncomplete": duplicates.cancelled || duplicates.limited || !duplicates.issues.isEmpty,
            "receipts": trashReceipts(receipts, root: root)]
        if let malware {
            state["malware"] = ["scanned": malware.scanned, "skipped": malware.skipped,
                "findings": malware.findings.count, "failed": malware.failed,
                "incomplete": malware.incomplete, "cancelled": malware.cancelled]
        }
        return try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
    }

    private static func duplicateGroups(_ groups: [StorageDuplicateGroup], root: URL) -> [[String: Any]] {
        groups.compactMap { group in
            guard !group.files.isEmpty, group.files.allSatisfy({ within($0.url, root) }) else { return nil }
            var result: [String: Any] = ["id": group.id.uuidString, "files": group.files.map(\.id)]
            if let keeper = group.keeperID, group.files.contains(where: { $0.id == keeper }) { result["keeper"] = keeper }
            return result
        }
    }

    private static func trashReceipts(_ receipts: [StorageTrashReceipt], root: URL) -> [[String: Any]] {
        receipts.filter { within($0.original, root) }.map { receipt in
            var result: [String: Any] = ["original": receipt.original.path]
            if let trash = receipt.trash { result["trash"] = trash.path }
            if let failure = receipt.failure {
                result["failure"] = StorageInspectionFailure(rawValue: failure)?.rawValue ?? StorageInspectionFailure.failed.rawValue
            }
            return result
        }
    }

    private static func within(_ url: URL, _ root: URL) -> Bool {
        StorageInspectionPolicy.isWithin(url.standardizedFileURL, root: root.standardizedFileURL)
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct StorageFileSnapshot: Equatable, Identifiable {
    let url: URL
    let root: URL
    let identity: UninstallerSupport.FileIdentity
    let logicalBytes: Int64
    let allocatedBytes: Int64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let ancestors: [StorageAncestor]
    var id: String { url.path }
    var modified: Date? {
        modifiedSeconds > 0 ? Date(timeIntervalSince1970: Double(modifiedSeconds) + Double(modifiedNanoseconds) / 1e9) : nil
    }
}

struct StorageAncestor: Equatable {
    let url: URL
    let identity: UninstallerSupport.FileIdentity
}

struct StorageFolderTotal: Identifiable {
    let url: URL
    var bytes: Int64 = 0
    var files = 0
    var id: String { url.path }
}

struct StorageScanResult {
    var files: [StorageFileSnapshot] = []
    var folders: [String: StorageFolderTotal] = [:]
    var issues: [StorageScanIssue] = []
    var skipped = 0
    var denied = 0
    var visited = 0
    var cancelled = false
    var limited = false
    var isPartial: Bool { cancelled || limited || skipped > 0 || denied > 0 || !issues.isEmpty }
    var totalBytes: Int64 { files.reduce(0) { $0 + $1.allocatedBytes } }
}

struct StorageScanIssue: Identifiable {
    let id = UUID()
    let path: String
    let reason: StorageInspectionFailure
}

enum StorageInspectionFailure: String, Error {
    case excluded, unavailable, changed, denied, cancelled, limit, missingKeeper, failed
}

struct StorageDuplicateGroup: Identifiable {
    let id = UUID()
    let files: [StorageFileSnapshot]
    var keeperID: String?
}

struct StorageTrashReceipt: Identifiable {
    let id = UUID()
    let original: URL
    let trash: URL?
    let failure: String?
}

struct StorageInspectionLimits {
    var files = 50_000
    var directories = 10_000
    var seconds: TimeInterval = 120
    var hashBytes: Int64 = 32 * 1_024 * 1_024 * 1_024
}

enum StorageInspectionPolicy {
    static func isWithin(_ url: URL, root: URL) -> Bool {
        url.path == root.path || url.path.hasPrefix(root.path + "/")
    }

    static func isOld(_ file: StorageFileSnapshot, days: Int, now: Date = Date()) -> Bool {
        guard days > 0, let modified = file.modified else { return false }
        return modified < now.addingTimeInterval(-Double(days) * 86_400)
    }

    static func removalsAllowed(_ ids: Set<String>, groups: [StorageDuplicateGroup]) -> Bool {
        groups.allSatisfy { group in
            let chosen = group.files.filter { ids.contains($0.id) }
            guard !chosen.isEmpty else { return true }
            guard let keeper = group.keeperID, group.files.contains(where: { $0.id == keeper }) else { return false }
            return !ids.contains(keeper) && chosen.count < group.files.count
        }
    }
}

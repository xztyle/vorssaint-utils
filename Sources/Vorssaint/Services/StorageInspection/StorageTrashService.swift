// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum StorageTrashService {
    typealias Move = (URL) throws -> URL

    static func move(_ files: [StorageFileSnapshot], groups: [StorageDuplicateGroup],
                     cancellation: CleanerSupport.ScanCancellation, mover: Move = trash) -> [StorageTrashReceipt] {
        StorageLocalAccess.withoutMaterializing {
            let ids = Set(files.map(\.id))
            guard StorageInspectionPolicy.removalsAllowed(ids, groups: groups), keepersRemain(groups, selected: ids) else {
                return files.map { .init(original: $0.url, trash: nil, failure: StorageInspectionFailure.missingKeeper.rawValue) }
            }
            return files.map { file in
                do {
                    if cancellation.isCancelled { throw StorageInspectionFailure.cancelled }
                    guard keepersRemain(groups, selected: ids) else { throw StorageInspectionFailure.missingKeeper }
                    try StorageLocalAccess.validate(file)
                    return .init(original: file.url, trash: try mover(file.url), failure: nil)
                } catch { return .init(original: file.url, trash: nil, failure: (error as? StorageInspectionFailure)?.rawValue ?? error.localizedDescription) }
            }
        }
    }

    private static func keepersRemain(_ groups: [StorageDuplicateGroup], selected: Set<String>) -> Bool {
        groups.allSatisfy { group in
            guard group.files.contains(where: { selected.contains($0.id) }) else { return true }
            guard let keeper = group.files.first(where: { $0.id == group.keeperID }) else { return false }
            return (try? StorageLocalAccess.validate(keeper)) != nil
        }
    }

    private static func trash(_ url: URL) throws -> URL {
        var destination: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &destination)
        guard let destination else { throw StorageInspectionFailure.failed }
        return destination as URL
    }
}

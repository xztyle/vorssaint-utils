// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CryptoKit
import Foundation

struct StorageDuplicateResult {
    var groups: [StorageDuplicateGroup] = []
    var issues: [StorageScanIssue] = []
    var cancelled = false
    var limited = false
}

enum StorageDuplicateFinder {
    private final class Budget {
        let cancellation: CleanerSupport.ScanCancellation
        let deadline: Date
        var remaining: Int64
        init(_ cancellation: CleanerSupport.ScanCancellation, _ limits: StorageInspectionLimits) {
            self.cancellation = cancellation
            deadline = Date().addingTimeInterval(limits.seconds)
            remaining = limits.hashBytes
        }
        func consume(_ bytes: Int) throws {
            if cancellation.isCancelled { throw StorageInspectionFailure.cancelled }
            remaining -= Int64(bytes)
            if remaining < 0 || Date() > deadline { throw StorageInspectionFailure.limit }
        }
    }

    static func find(_ files: [StorageFileSnapshot], cancellation: CleanerSupport.ScanCancellation,
                     limits: StorageInspectionLimits = .init()) -> StorageDuplicateResult {
        StorageLocalAccess.withoutMaterializing {
            let budget = Budget(cancellation, limits)
            var result = StorageDuplicateResult()
            var seen = Set<UninstallerSupport.FileIdentity>()
            let distinct = files.filter { seen.insert($0.identity).inserted }
            for candidates in Dictionary(grouping: distinct, by: \.logicalBytes).values where candidates.count > 1 {
                do { try group(candidates, budget: budget, result: &result) }
                catch {
                    result.cancelled = (error as? StorageInspectionFailure) == .cancelled
                    result.limited = (error as? StorageInspectionFailure) == .limit
                    if result.cancelled || result.limited { break }
                }
            }
            return result
        }
    }

    private static func group(_ files: [StorageFileSnapshot], budget: Budget, result: inout StorageDuplicateResult) throws {
        var hashes: [String: [StorageFileSnapshot]] = [:]
        for file in files {
            do { hashes[try hash(file, budget: budget), default: []].append(file) }
            catch { try record(error, file: file, result: &result) }
        }
        for values in hashes.values where values.count > 1 {
            var buckets: [[StorageFileSnapshot]] = []
            for file in values {
                do {
                    if let index = try buckets.firstIndex(where: { try equal($0[0], file, budget: budget) }) {
                        buckets[index].append(file)
                    } else { buckets.append([file]) }
                } catch { try record(error, file: file, result: &result) }
            }
            result.groups += buckets.filter { $0.count > 1 }.map { .init(files: $0, keeperID: nil) }
        }
    }

    private static func record(_ error: Error, file: StorageFileSnapshot, result: inout StorageDuplicateResult) throws {
        let reason = error as? StorageInspectionFailure ?? .unavailable
        if reason == .cancelled || reason == .limit { throw reason }
        if result.issues.count < 200 { result.issues.append(.init(path: file.id, reason: reason)) }
    }

    private static func hash(_ file: StorageFileSnapshot, budget: Budget) throws -> String {
        let handle = try StorageLocalAccess.openVerified(file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            try budget.consume(0)
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            guard !data.isEmpty else { break }
            try budget.consume(data.count)
            hasher.update(data: data)
        }
        try StorageLocalAccess.validateEnd(handle, file: file)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func equal(_ lhs: StorageFileSnapshot, _ rhs: StorageFileSnapshot, budget: Budget) throws -> Bool {
        let left = try StorageLocalAccess.openVerified(lhs)
        defer { try? left.close() }
        let right = try StorageLocalAccess.openVerified(rhs)
        defer { try? right.close() }
        while true {
            try budget.consume(0)
            let a = try left.read(upToCount: 1_048_576) ?? Data()
            let b = try right.read(upToCount: 1_048_576) ?? Data()
            try budget.consume(a.count + b.count)
            guard a == b else { return false }
            if a.isEmpty { break }
        }
        try StorageLocalAccess.validateEnd(left, file: lhs)
        try StorageLocalAccess.validateEnd(right, file: rhs)
        return true
    }
}

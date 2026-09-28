// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import Darwin

enum StorageFolderScanner {
    static func scan(roots: [URL], cancellation: CleanerSupport.ScanCancellation,
                     limits: StorageInspectionLimits = .init(), progress: (Int) -> Void = { _ in }) -> StorageScanResult {
        StorageLocalAccess.withoutMaterializing {
            var result = StorageScanResult()
            var seen = Set<UninstallerSupport.FileIdentity>()
            let deadline = Date().addingTimeInterval(limits.seconds)
            for root in roots.prefix(8) {
                if cancellation.isCancelled { result.cancelled = true; break }
                do {
                    let canonical = try StorageLocalAccess.canonicalRoot(root)
                    walk(root: canonical, result: &result, seen: &seen,
                         cancellation: cancellation, limits: limits, deadline: deadline, progress: progress)
                } catch { report(root, error, into: &result) }
                if result.limited || result.cancelled { break }
            }
            return result
        }
    }

    private static func walk(root: URL, result: inout StorageScanResult,
                             seen: inout Set<UninstallerSupport.FileIdentity>, cancellation: CleanerSupport.ScanCancellation,
                             limits: StorageInspectionLimits, deadline: Date, progress: (Int) -> Void) {
        do {
            guard root.pathComponents.count > 2, root.path != NSHomeDirectory(),
                  !["/Applications", "/System", "/Users", "/Library", "/Volumes", "/private", "/usr", "/bin", "/sbin", "/opt"].contains(root.path)
            else { throw StorageInspectionFailure.excluded }
            let info = try StorageLocalAccess.metadata(root)
            guard (info.st_mode & S_IFMT) == S_IFDIR else { throw StorageInspectionFailure.excluded }
            let rootAncestors = try StorageLocalAccess.ancestors(of: root) + [.init(url: root, identity: StorageLocalAccess.identity(info))]
            var pending = [root]
            while let directory = pending.popLast() {
                if cancellation.isCancelled { result.cancelled = true; break }
                if Date() > deadline || result.files.count >= limits.files || result.folders.count >= limits.directories {
                    result.limited = true; break
                }
                try StorageLocalAccess.validateAncestors(rootAncestors)
                visit(directory, root: root, device: info.st_dev, pending: &pending, result: &result, seen: &seen, limits: limits, deadline: deadline, cancellation: cancellation)
                progress(result.visited)
            }
        } catch { report(root, error, into: &result) }
    }

    private static func visit(_ directory: URL, root: URL, device: dev_t, pending: inout [URL],
                              result: inout StorageScanResult, seen: inout Set<UninstallerSupport.FileIdentity>,
                              limits: StorageInspectionLimits, deadline: Date, cancellation: CleanerSupport.ScanCancellation) {
        do {
            _ = try StorageLocalAccess.metadata(directory)
            result.folders[directory.path] = result.folders[directory.path] ?? .init(url: directory)
            guard let handle = opendir(directory.path) else { throw StorageInspectionFailure.denied }
            defer { closedir(handle) }
            while let entry = readdir(handle) {
                if cancellation.isCancelled { result.cancelled = true; break }
                if Date() > deadline || result.files.count >= limits.files || pending.count + result.folders.count >= limits.directories {
                    result.limited = true; break
                }
                let name = withUnsafePointer(to: &entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
                }
                if name == "." || name == ".." { continue }
                result.visited += 1
                admit(directory.appendingPathComponent(name), root: root, device: device, pending: &pending, result: &result, seen: &seen)
            }
        } catch { report(directory, error, into: &result) }
    }

    private static func admit(_ url: URL, root: URL, device: dev_t, pending: inout [URL],
                              result: inout StorageScanResult, seen: inout Set<UninstallerSupport.FileIdentity>) {
        do {
            let value = try StorageLocalAccess.metadata(url)
            guard value.st_dev == device else { throw StorageInspectionFailure.excluded }
            if (value.st_mode & S_IFMT) == S_IFDIR {
                pending.append(url)
            } else {
                let file = try StorageLocalAccess.snapshot(url, root: root, value: value)
                guard seen.insert(file.identity).inserted else { throw StorageInspectionFailure.excluded }
                result.files.append(file)
                addSize(file, result: &result)
            }
        } catch { report(url, error, into: &result) }
    }

    private static func addSize(_ file: StorageFileSnapshot, result: inout StorageScanResult) {
        var folder = file.url.deletingLastPathComponent()
        while StorageInspectionPolicy.isWithin(folder, root: file.root) {
            var total = result.folders[folder.path] ?? .init(url: folder)
            total.bytes += file.allocatedBytes
            total.files += 1
            result.folders[folder.path] = total
            if folder == file.root { break }
            folder.deleteLastPathComponent()
        }
    }

    private static func report(_ url: URL, _ error: Error, into result: inout StorageScanResult) {
        let reason = error as? StorageInspectionFailure ?? .denied
        if reason == .excluded { result.skipped += 1 } else { result.denied += 1 }
        if result.issues.count < 200 { result.issues.append(.init(path: url.path, reason: reason)) }
    }
}

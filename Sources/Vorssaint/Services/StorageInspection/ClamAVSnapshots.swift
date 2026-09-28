// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// Only our marked private scan copies may be removed after an interrupted run.
enum ClamAVSnapshots {
    static func create(in root: URL) throws -> URL {
        try discardInterrupted(in: root)
        let directory = root.appendingPathComponent("Scan-" + UUID().uuidString, isDirectory: true)
        guard PrivateFileStore.createDirectory(at: directory, container: root),
              PrivateFileStore.write(marker(directory), to: directory.appendingPathComponent(".aster-snapshot")) else {
            throw StorageInspectionFailure.failed
        }
        return directory
    }

    static func discardInterrupted(in root: URL) throws {
        guard let handle = opendir(root.path) else { throw StorageInspectionFailure.denied }
        defer { closedir(handle) }
        var count = 0
        while let entry = readdir(handle) {
            count += 1
            guard count <= 512 else { throw StorageInspectionFailure.limit }
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            guard name.hasPrefix("Scan-"), UUID(uuidString: String(name.dropFirst(5))) != nil else { continue }
            let directory = root.appendingPathComponent(name, isDirectory: true)
            guard owned(directory) else { continue }
            try FileManager.default.removeItem(at: directory)
        }
    }

    static func marker(_ directory: URL) -> Data {
        Data(("Aster private malware snapshot 1\n" + directory.path + "\n").utf8)
    }

    private static func owned(_ directory: URL) -> Bool {
        var metadata = stat()
        guard lstat(directory.path, &metadata) == 0, (metadata.st_mode & S_IFMT) == S_IFDIR,
              metadata.st_uid == geteuid(), metadata.st_mode & 0o077 == 0 else { return false }
        let url = directory.appendingPathComponent(".aster-snapshot")
        guard !UninstallerSupport.isSymbolicLink(url), let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 4096)) == marker(directory)
    }
}

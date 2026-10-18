// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import Foundation

extension ClamAVBackend {
    /// Reuse only independently verified complete CVDs and their signatures.
    /// A CLD assembled from patches is fetched again as a complete signed CVD.
    func seedVerifiedDefinitions(from existing: URL, cancellation: BoundedProcessCancellation) throws {
        for name in ["main", "daily", "bytecode"] {
            if cancellation.isCancelled { throw StorageInspectionFailure.cancelled }
            let file = existing.appendingPathComponent(name + ".cvd")
            guard !UninstallerSupport.isSymbolicLink(file), let signature = definitionSignature(file),
                  !UninstallerSupport.isSymbolicLink(signature), FileManager.default.fileExists(atPath: signature.path) else { continue }
            let result = run(tools.verifier, ["--cvdcertsdir=" + tools.certificates, "--verify", file.path], 45, cancellation)
            guard result.status == 0, !result.timedOut else { continue }
            try FileManager.default.copyItem(at: file, to: database.appendingPathComponent(file.lastPathComponent))
            try FileManager.default.copyItem(at: signature, to: database.appendingPathComponent(signature.lastPathComponent))
        }
    }

    private func definitionSignature(_ file: URL) -> URL? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let bytes = try? handle.read(upToCount: 512), let header = String(data: bytes, encoding: .utf8) else { return nil }
        let fields = header.components(separatedBy: ":")
        guard fields.count > 2, fields[0] == "ClamAV-VDB", let version = UInt32(fields[2]), version > 0 else { return nil }
        let name = file.deletingPathExtension().lastPathComponent + "-\(version).cvd.sign"
        return file.deletingLastPathComponent().appendingPathComponent(name)
    }

    func publishDefinitions(from staged: URL) throws {
        guard !UninstallerSupport.isSymbolicLink(root), !UninstallerSupport.isSymbolicLink(database),
              !UninstallerSupport.isSymbolicLink(staged) else { throw StorageInspectionFailure.excluded }
        let backup = root.appendingPathComponent("Definitions-previous-" + UUID().uuidString)
        try FileManager.default.moveItem(at: database, to: backup)
        do { try FileManager.default.moveItem(at: staged, to: database) }
        catch {
            try FileManager.default.moveItem(at: backup, to: database)
            throw error
        }
        try? FileManager.default.removeItem(at: backup) // Re-downloadable app cache only.
    }
}

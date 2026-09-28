// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The external one-shot engine gets only private snapshots of eligible local
/// files. Originals cannot be changed, followed through links, or quarantined.
final class ClamAVBackend {
    typealias Runner = (String, [String], TimeInterval, BoundedProcessCancellation) -> BoundedProcessRunner.Result
    let tools: ClamAVTools
    let root: URL
    let run: Runner
    var database: URL { root.appendingPathComponent("Definitions", isDirectory: true) }

    init(tools: ClamAVTools, root: URL, run: @escaping Runner = ClamAVBackend.execute) {
        self.tools = tools; self.root = root; self.run = run
    }

    static func execute(_ path: String, _ args: [String], _ timeout: TimeInterval,
                        _ cancellation: BoundedProcessCancellation) -> BoundedProcessRunner.Result {
        BoundedProcessRunner.run(path, args, timeout: timeout, maxOutputBytes: 1_048_576,
            environment: ["PATH": "/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin", "HOME": NSHomeDirectory(), "LC_ALL": "C"],
            cancellation: cancellation)
    }

    func definitionDate() -> Date? {
        guard let daily = databaseFiles().first(where: { $0.lastPathComponent.hasPrefix("daily.") }),
              let handle = try? FileHandle(forReadingFrom: daily) else { return nil }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 512)).flatMap { $0 }.flatMap(ClamAVSupport.definitionDate)
    }

    func verify(_ cancellation: BoundedProcessCancellation) throws {
        let files = databaseFiles()
        guard files.count == 3, ClamAVSupport.fresh(definitionDate()) else { throw StorageInspectionFailure.unavailable }
        for file in files {
            if cancellation.isCancelled { throw StorageInspectionFailure.cancelled }
            let result = run(tools.verifier, ["--cvdcertsdir=" + tools.certificates, "--verify", file.path], 45, cancellation)
            guard result.status == 0, !result.timedOut else { throw ClamAVBackendError.verification(String(decoding: result.output, as: UTF8.self)) }
        }
    }

    func update(_ cancellation: BoundedProcessCancellation) throws -> String {
        try prepareDirectory()
        guard !database.path.contains("\n"), !database.path.contains("\"") else { throw StorageInspectionFailure.excluded }
        let config = root.appendingPathComponent("freshclam.conf")
        let text = "DatabaseDirectory \"\(database.path)\"\nDatabaseMirror database.clamav.net\nTestDatabases yes\nScriptedUpdates no\n"
        guard PrivateFileStore.write(Data(text.utf8), to: config) else { throw StorageInspectionFailure.failed }
        let result = run(tools.updater, ["--config-file=" + config.path, "--cvdcertsdir=" + tools.certificates], 600, cancellation)
        let detail = String(decoding: result.output, as: UTF8.self)
        guard result.status == 0, !result.timedOut, !cancellation.isCancelled else { throw ClamAVBackendError.update(detail) }
        try verify(cancellation)
        return detail
    }

    func scan(_ files: [StorageFileSnapshot], cancellation: CleanerSupport.ScanCancellation,
              processCancellation: BoundedProcessCancellation) -> ClamAVScanResult {
        do {
            try prepareDirectory()
            try verify(processCancellation)
            return try StorageLocalAccess.withoutMaterializing {
                try scanSnapshots(files, cancellation: cancellation, processCancellation: processCancellation)
            }
        } catch {
            return .init(incomplete: true, failed: true, cancelled: cancellation.isCancelled || processCancellation.isCancelled,
                         detail: error.localizedDescription)
        }
    }

    private func scanSnapshots(_ files: [StorageFileSnapshot], cancellation: CleanerSupport.ScanCancellation,
                               processCancellation: BoundedProcessCancellation) throws -> ClamAVScanResult {
        let temporary = try ClamAVSnapshots.create(in: root)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let stage = try stage(files, into: temporary, cancellation: cancellation)
        guard !stage.mapping.isEmpty else { return .init(incomplete: true, skipped: stage.skipped) }
        let list = temporary.appendingPathComponent("files.txt")
        guard PrivateFileStore.write(Data(stage.mapping.keys.sorted().joined(separator: "\n").utf8), to: list) else { throw StorageInspectionFailure.failed }
        let result = run(tools.scanner, ClamAVSupport.arguments(database: database, list: list, temporary: temporary,
                          certificates: tools.certificates), 300, processCancellation)
        var report = ClamAVSupport.parse(status: result.status, output: String(decoding: result.output, as: UTF8.self),
            timedOut: result.timedOut, cancelled: processCancellation.isCancelled, mapping: stage.mapping)
        report.skipped = stage.skipped
        report.incomplete = report.incomplete || stage.skipped > 0
        return report
    }

    private func stage(_ files: [StorageFileSnapshot], into directory: URL, cancellation: CleanerSupport.ScanCancellation)
        throws -> (mapping: [String: String], skipped: Int) {
        var mapping: [String: String] = [:]
        var bytes: Int64 = 0
        var skipped = 0
        let deadline = Date().addingTimeInterval(120)
        for (index, file) in files.enumerated() {
            if cancellation.isCancelled { throw StorageInspectionFailure.cancelled }
            guard mapping.count < ClamAVSupport.maximumFiles, file.logicalBytes <= ClamAVSupport.maximumFileBytes,
                  bytes + file.logicalBytes <= ClamAVSupport.maximumTotalBytes, Date() < deadline else { skipped += 1; continue }
            let target = directory.appendingPathComponent(String(format: "%05d", index) + ".scan")
            do {
                try copy(file, to: target, cancellation: cancellation)
                bytes += file.logicalBytes
                mapping[target.path] = file.id
            } catch { skipped += 1; try? FileManager.default.removeItem(at: target) }
        }
        return (mapping, skipped)
    }

    private func copy(_ file: StorageFileSnapshot, to target: URL, cancellation: CleanerSupport.ScanCancellation) throws {
        let input = try StorageLocalAccess.openVerified(file)
        defer { try? input.close() }
        guard FileManager.default.createFile(atPath: target.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw StorageInspectionFailure.failed }
        let output = try FileHandle(forWritingTo: target)
        defer { try? output.close() }
        var remaining = file.logicalBytes
        while remaining > 0 {
            if cancellation.isCancelled { throw StorageInspectionFailure.cancelled }
            let data = try input.read(upToCount: Int(min(remaining, 1_048_576))) ?? Data()
            guard !data.isEmpty else { throw StorageInspectionFailure.changed }
            try output.write(contentsOf: data)
            remaining -= Int64(data.count)
        }
        try StorageLocalAccess.validateEnd(input, file: file)
    }

    private func databaseFiles() -> [URL] {
        ["main", "daily", "bytecode"].compactMap { name in
            ["cvd", "cld"].map { database.appendingPathComponent(name + "." + $0) }
                .first { FileManager.default.fileExists(atPath: $0.path) && !UninstallerSupport.isSymbolicLink($0) }
        }
    }

    private func prepareDirectory() throws {
        guard !UninstallerSupport.isSymbolicLink(root), !UninstallerSupport.isSymbolicLink(database),
              PrivateFileStore.createDirectory(at: database, container: root) else { throw StorageInspectionFailure.failed }
    }
}

enum ClamAVBackendError: LocalizedError {
    case verification(String), update(String)
    var errorDescription: String? {
        switch self { case .verification(let detail), .update(let detail): return detail }
    }
}

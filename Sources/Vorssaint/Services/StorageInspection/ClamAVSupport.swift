// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct ClamAVTools {
    let scanner: String
    let updater: String
    let verifier: String
    let certificates: String

    static func detect() -> ClamAVTools? {
        for (bin, certs) in [("/opt/homebrew/bin", "/opt/homebrew/etc/clamav/certs"),
                              ("/usr/local/bin", "/usr/local/etc/clamav/certs"),
                              ("/usr/local/clamav/bin", "/usr/local/clamav/etc/certs")] {
            let paths = ["clamscan", "freshclam", "sigtool"].map { bin + "/" + $0 }
            if paths.allSatisfy({ FileManager.default.isExecutableFile(atPath: $0) }),
               FileManager.default.fileExists(atPath: certs) {
                return .init(scanner: paths[0], updater: paths[1], verifier: paths[2], certificates: certs)
            }
        }
        return nil
    }
}

struct ClamAVFinding: Identifiable {
    let id = UUID()
    let path: String
    let signature: String
}

struct ClamAVScanResult {
    var findings: [ClamAVFinding] = []
    var incomplete = false
    var failed = false
    var cancelled = false
    var scanned = 0
    var skipped = 0
    var detail = ""
}

enum ClamAVSupport {
    static let maximumFileBytes: Int64 = 256 * 1_024 * 1_024
    static let maximumTotalBytes: Int64 = 2 * 1_024 * 1_024 * 1_024
    static let maximumFiles = 2_000
    static let maximumDefinitionAge: TimeInterval = 7 * 86_400

    static func definitionDate(header: Data) -> Date? {
        guard let text = String(data: header, encoding: .utf8), text.hasPrefix("ClamAV-VDB:"),
              let last = text.split(separator: ":").last,
              let epoch = TimeInterval(last.trimmingCharacters(in: .whitespacesAndNewlines)), epoch > 0 else { return nil }
        return Date(timeIntervalSince1970: epoch)
    }

    static func fresh(_ date: Date?, now: Date = Date()) -> Bool {
        guard let date else { return false }
        return date <= now.addingTimeInterval(86_400) && now.timeIntervalSince(date) <= maximumDefinitionAge
    }

    static func arguments(database: URL, list: URL, temporary: URL, certificates: String) -> [String] {
        ["--database=" + database.path, "--file-list=" + list.path, "--tempdir=" + temporary.path,
         "--cvdcertsdir=" + certificates, "--official-db-only=yes", "--fail-if-cvd-older-than=7",
         "--follow-dir-symlinks=0", "--follow-file-symlinks=0", "--cross-fs=no", "--recursive=no",
         "--alert-exceeds-max=yes", "--alert-encrypted=yes", "--max-filesize=256M", "--max-scansize=512M",
         "--max-files=1000", "--max-recursion=12", "--max-scantime=0", "--suppress-ok-results"]
    }

    static func parse(status: Int32, output: String, timedOut: Bool, cancelled: Bool,
                      mapping: [String: String]) -> ClamAVScanResult {
        var result = ClamAVScanResult()
        result.failed = status != 0 && status != 1
        result.cancelled = cancelled
        result.incomplete = timedOut || cancelled || result.failed || output.utf8.count >= 1_048_576
        result.detail = String(output.suffix(16_000))
        for line in output.components(separatedBy: .newlines) {
            if line.hasPrefix("Scanned files:"), let count = Int(line.dropFirst(14).trimmingCharacters(in: .whitespaces)) { result.scanned = count }
            if line.contains("ERROR") || line.contains("WARNING") || line.contains("time limit") { result.incomplete = true }
            guard line.hasSuffix(" FOUND"), let separator = line.range(of: ": ", options: .backwards) else { continue }
            let signature = String(line[separator.upperBound...].dropLast(6))
            if signature.contains("Exceeded") || signature.contains("Encrypted") || signature.contains("Max") {
                result.incomplete = true; continue
            }
            let source = String(line[..<separator.lowerBound])
            guard let path = mapping[source] else { result.incomplete = true; continue }
            result.findings.append(.init(path: path, signature: signature))
        }
        if result.scanned < mapping.count || (status == 1 && result.findings.isEmpty) { result.incomplete = true }
        return result
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import Darwin

struct SecurityInspectionRow: Identifiable {
    let id = UUID()
    let url: URL
    var label: String
    var executable: String?
    var signature: Signature = .unknown
    var teamID: String?
    var gatekeeper: Assessment = .unknown
    var quarantined = false
    var detail = ""
    enum Signature: String { case valid, unsigned, invalid, unknown }
    enum Assessment: String { case accepted, rejected, unknown }
}

struct SecurityInspectionReport {
    var rows: [SecurityInspectionRow] = []
    var partial = false
}

enum SecurityInspector {
    typealias Runner = (String, [String], TimeInterval, BoundedProcessCancellation) -> BoundedProcessRunner.Result

    private static func execute(_ path: String, _ arguments: [String], _ timeout: TimeInterval,
                                _ cancellation: BoundedProcessCancellation) -> BoundedProcessRunner.Result {
        BoundedProcessRunner.run(path, arguments, timeout: timeout, maxOutputBytes: 16_384,
                                 environment: ["LC_ALL": "C"], cancellation: cancellation)
    }

    private static func local(_ url: URL) -> Bool {
        guard (try? StorageLocalAccess.canonicalRoot(url)) != nil else { return false }
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_flags & UInt32(SF_DATALESS) == 0,
              let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .volumeIsLocalKey]) else { return false }
        return values.isUbiquitousItem != true && values.volumeIsLocal == true
            && !url.pathComponents.contains { ["CloudStorage", "Mobile Documents"].contains($0) }
    }

    static func inspectApps(_ urls: [URL], cancellation: BoundedProcessCancellation) -> SecurityInspectionReport {
        var report = SecurityInspectionReport()
        report.partial = urls.count > 200
        let deadline = Date().addingTimeInterval(120)
        for url in urls.prefix(200) {
            if cancellation.isCancelled || Date() > deadline { report.partial = true; break }
            guard local(url) else { report.rows.append(.init(url: url, label: url.lastPathComponent)); report.partial = true; continue }
            var row = signature(url, cancellation: cancellation, deadline: deadline)
            guard !cancellation.isCancelled, Date() < deadline else { report.rows.append(row); report.partial = true; break }
            let result = BoundedProcessRunner.run("/usr/sbin/spctl", ["--assess", "--type", "execute", "--verbose=2", url.path],
                timeout: min(8, deadline.timeIntervalSinceNow), maxOutputBytes: 16_384, environment: ["LC_ALL": "C"], cancellation: cancellation)
            row.detail = String(decoding: result.output, as: UTF8.self)
            if !result.timedOut && !cancellation.isCancelled {
                row.gatekeeper = result.status == 0 ? .accepted : row.detail.contains("rejected") ? .rejected : .unknown
            }
            if result.timedOut || cancellation.isCancelled || row.gatekeeper == .unknown || row.signature == .unknown { report.partial = true }
            report.rows.append(row)
        }
        return report
    }

    static func signature(_ url: URL, cancellation: BoundedProcessCancellation = .init(),
                          deadline: Date = Date().addingTimeInterval(8), run: Runner = execute) -> SecurityInspectionRow {
        var row = SecurityInspectionRow(url: url, label: url.lastPathComponent)
        guard local(url), !cancellation.isCancelled, Date() < deadline else { return row }
        row.quarantined = getxattr(url.path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW) > 0
        let verified = run("/usr/bin/codesign", ["--verify", "--strict", "--all-architectures", url.path], min(8, deadline.timeIntervalSinceNow), cancellation)
        row.detail = String(decoding: verified.output, as: UTF8.self)
        guard !verified.timedOut, !cancellation.isCancelled else { return row }
        row.signature = verified.status == 0 ? .valid : row.detail.contains("not signed at all") ? .unsigned
            : row.detail.contains("invalid") || row.detail.contains("modified") || row.detail.contains("not valid") ? .invalid : .unknown
        guard Date() < deadline else { return row }
        let metadata = run("/usr/bin/codesign", ["--display", "--verbose=2", url.path], min(4, deadline.timeIntervalSinceNow), cancellation)
        if metadata.status == 0, !metadata.timedOut {
            let lines = String(decoding: metadata.output, as: UTF8.self).components(separatedBy: .newlines)
            row.teamID = lines.first { $0.hasPrefix("TeamIdentifier=") }.map { String($0.dropFirst(15)) }
        }
        return row
    }

    static func startupEntries(roots: [URL], cancellation: CleanerSupport.ScanCancellation,
                               processCancellation: BoundedProcessCancellation = .init()) -> SecurityInspectionReport {
        var report = SecurityInspectionReport()
        let deadline = Date().addingTimeInterval(30)
        for root in roots {
            guard !UninstallerSupport.isSymbolicLink(root), let handle = opendir(root.path) else {
                report.partial = true
                report.rows.append(.init(url: root, label: root.path))
                continue
            }
            defer { closedir(handle) }
            var count = 0
            while let entry = readdir(handle) {
                if cancellation.isCancelled || processCancellation.isCancelled || Date() > deadline || count >= 200 { report.partial = true; break }
                let name = withUnsafePointer(to: &entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
                }
                guard name.hasSuffix(".plist") else { continue }
                report.rows.append(startup(root.appendingPathComponent(name), cancellation: processCancellation, deadline: deadline))
                count += 1
            }
        }
        return report
    }

    private static func startup(_ url: URL, cancellation: BoundedProcessCancellation, deadline: Date) -> SecurityInspectionRow {
        var row = SecurityInspectionRow(url: url, label: url.lastPathComponent)
        guard !UninstallerSupport.isSymbolicLink(url), let handle = try? FileHandle(forReadingFrom: url) else { return row }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 65_537), data.count <= 65_536,
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return row }
        row.label = plist["Label"] as? String ?? row.label
        row.executable = plist["Program"] as? String ?? (plist["ProgramArguments"] as? [String])?.first
        if let path = row.executable, path.hasPrefix("/"), FileManager.default.fileExists(atPath: path) {
            let evidence = signature(URL(fileURLWithPath: path), cancellation: cancellation, deadline: deadline)
            row.signature = evidence.signature
            row.teamID = evidence.teamID
        }
        return row
    }
}

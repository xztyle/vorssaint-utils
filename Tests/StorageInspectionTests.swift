// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import Darwin

enum StorageInspectionTests {
    static func run(_ suite: TestSuite) {
        do { try fixtures(suite) } catch { suite.expect(false, "storage fixture failed: \(error)") }
        policies(suite)
        engineResults(suite)
        locales(suite)
    }

    private static func fixtures(_ suite: TestSuite) throws {
        let root = try StorageLocalAccess.canonicalRoot(FileManager.default.temporaryDirectory).appendingPathComponent("AsterStorageTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        try prepareFiles(root)
        let result = StorageFolderScanner.scan(roots: [root], cancellation: .init())
        suite.expect(result.files.count == 3 && result.skipped == 3 && result.isPartial, "scan excludes hard-link aliases, symlinks and packages with visible skipped coverage")
        let duplicates = StorageDuplicateFinder.find(result.files, cancellation: .init())
        suite.expect(duplicates.groups.count == 1 && duplicates.groups[0].files.count == 2, "full streamed hash plus byte comparison finds exact content despite names, and rejects same-size different bytes")
        guard let firstGroup = duplicates.groups.first else { return }
        suite.expect(firstGroup.keeperID == nil, "duplicate groups start without a silently chosen keeper")
        try removals(suite, root: root, files: result.files, groups: duplicates.groups)
        try parentReplacement(suite, root: root)
        try sharedAndDates(suite, root: root, file: result.files[0])
        let limited = StorageFolderScanner.scan(roots: [root], cancellation: .init(), limits: .init(files: 1))
        suite.expect(limited.limited && limited.files.count <= 1, "enumeration stops at its retained-row budget")
        let cancelled = CleanerSupport.ScanCancellation(); cancelled.cancel()
        suite.expect(StorageFolderScanner.scan(roots: [root], cancellation: cancelled).cancelled, "cancelled enumeration reports cancellation")
        suite.expect(StorageDuplicateFinder.find(result.files, cancellation: cancelled).cancelled, "hash work observes cancellation before reading a chunk")
        try fixtureSafety(suite, root: root)
        try snapshotRecovery(suite, root: root)
        signatureResults(suite, file: root.appendingPathComponent("different.txt"))
        try engineGates(suite, root: root, files: result.files)
        try actualEngine(suite, root: root)
    }

    private static func prepareFiles(_ root: URL) throws {
        try Data("identical fixture\n".utf8).write(to: root.appendingPathComponent("original.txt"))
        try Data("identical fixture\n".utf8).write(to: root.appendingPathComponent("copy.txt"))
        try Data("different fixture\n".utf8).write(to: root.appendingPathComponent("different.txt"))
        try FileManager.default.linkItem(at: root.appendingPathComponent("original.txt"), to: root.appendingPathComponent("hardlink.txt"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("symbolic.txt"), withDestinationURL: root.appendingPathComponent("original.txt"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Skipped.app"), withIntermediateDirectories: true)
    }

    private static func removals(_ suite: TestSuite, root: URL, files: [StorageFileSnapshot], groups: [StorageDuplicateGroup]) throws {
        var groups = groups
        let chosen = groups[0].files[0]
        suite.expect(!StorageInspectionPolicy.removalsAllowed([chosen.id], groups: groups), "duplicate removal requires an explicit keeper")
        groups[0].keeperID = groups[0].files[1].id
        suite.expect(StorageInspectionPolicy.removalsAllowed([chosen.id], groups: groups), "one reviewed copy can be removed while its explicit keeper remains")
        suite.expect(!StorageInspectionPolicy.removalsAllowed(Set(groups[0].files.map(\.id)), groups: groups), "all copies can never be removed from a duplicate group")
        let rejected = StorageTrashService.move([chosen], groups: groups, cancellation: .init()) { _ in throw StorageInspectionFailure.denied }
        suite.expect(rejected[0].trash == nil && FileManager.default.fileExists(atPath: chosen.id), "failed Trash operation keeps the source and returns a path-specific failure")
        try Data("edited after review".utf8).write(to: chosen.url)
        var invoked = false
        let changed = StorageTrashService.move([chosen], groups: groups, cancellation: .init()) { url in invoked = true; return url }
        suite.expect(!invoked && changed[0].failure != nil, "changed size/time is refused before any removal")
        let fresh = StorageFolderScanner.scan(roots: [root], cancellation: .init()).files.first { $0.id == chosen.id }!
        let receipts = StorageTrashService.move([fresh], groups: [], cancellation: .init())
        if let trash = receipts.first?.trash {
            suite.expect(FileManager.default.fileExists(atPath: trash.path) && !FileManager.default.fileExists(atPath: fresh.id), "real Trash move of a generated fixture preserves its returned recovery URL")
            try FileManager.default.moveItem(at: trash, to: fresh.url)
        } else { suite.expect(false, "generated fixture Trash move failed: \(receipts.first?.failure ?? "unknown")") }
    }

    private static func parentReplacement(_ suite: TestSuite, root: URL) throws {
        let folder = root.appendingPathComponent("Parent")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("original nested fixture".utf8).write(to: folder.appendingPathComponent("child.txt"))
        let saved = StorageFolderScanner.scan(roots: [root], cancellation: .init()).files.first { $0.url.lastPathComponent == "child.txt" }!
        let moved = root.appendingPathComponent("PreviousParent")
        try FileManager.default.moveItem(at: folder, to: moved)
        try FileManager.default.createSymbolicLink(at: folder, withDestinationURL: moved)
        suite.expect((try? StorageLocalAccess.validate(saved)) == nil, "a parent replaced with a symlink is rejected despite matching file content")
        suite.expect((try? StorageLocalAccess.openVerified(saved)) == nil, "content reads also reject the swapped parent")
    }

    private static func sharedAndDates(_ suite: TestSuite, root: URL, file: StorageFileSnapshot) throws {
        let shared = root.appendingPathComponent("Shared-write.txt")
        try Data("fixture".utf8).write(to: shared)
        try FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: shared.path)
        suite.expect((try? StorageLocalAccess.metadata(shared)) == nil, "group/world-writable data is excluded from personal removal suggestions")
        let unknown = StorageFileSnapshot(url: file.url, root: file.root, identity: file.identity,
            logicalBytes: file.logicalBytes, allocatedBytes: file.allocatedBytes, modifiedSeconds: 0,
            modifiedNanoseconds: 0, ancestors: file.ancestors)
        suite.expect(unknown.modified == nil && !StorageInspectionPolicy.isOld(unknown, days: 1), "unknown modification dates never count as old")
        var value = stat()
        value.st_mode = S_IFREG; value.st_dev = dev_t(file.identity.device); value.st_ino = ino_t(file.identity.inode)
        value.st_size = file.logicalBytes; value.st_mtimespec.tv_sec = Int(file.modifiedSeconds)
        value.st_mtimespec.tv_nsec = Int(file.modifiedNanoseconds); value.st_flags = UInt32(SF_DATALESS)
        suite.expect(!StorageLocalAccess.matches(value, file), "a file changed into a dataless placeholder cannot be read or removed")
    }

    private static func policies(_ suite: TestSuite) {
        for path in ["/Users/person/Library/CloudStorage/provider/file", "/Users/person/Dropbox/file", "/Users/Shared/file", "/Users/person/.ssh/id_rsa", "/Users/person/a.photoslibrary/image", "/Users/person/secret.key"] {
            suite.expect(!StorageLocalAccess.pathEligible(URL(fileURLWithPath: path)), "protected/provider/package path excluded: \(path)")
        }
        suite.expect(!StorageInspectionPolicy.isWithin(URL(fileURLWithPath: "/tmp/scope-other/a"), root: URL(fileURLWithPath: "/tmp/scope")), "scope uses path component boundaries")
        let missing = StorageFolderScanner.scan(roots: [URL(fileURLWithPath: "/private/nonexistent-aster-fixture")], cancellation: .init())
        suite.expect(missing.isPartial && missing.denied > 0, "unavailable scope is partial, never an empty complete success")
    }

    private static func engineResults(_ suite: TestSuite) {
        let mapping = ["/private/scan/000.scan": "/chosen/file"]
        let good = ClamAVSupport.parse(status: 0, output: "Scanned files: 1\n", timedOut: false, cancelled: false, mapping: mapping)
        suite.expect(!good.failed && !good.incomplete && good.findings.isEmpty, "engine exit zero describes only the stated completed scope")
        let found = ClamAVSupport.parse(status: 1, output: "/private/scan/000.scan: Eicar-Test-Signature FOUND\nScanned files: 1\n", timedOut: false, cancelled: false, mapping: mapping)
        suite.expect(found.findings.count == 1 && found.findings[0].path == "/chosen/file", "matched staged file maps back to its reviewed original path")
        let limit = ClamAVSupport.parse(status: 1, output: "/private/scan/000.scan: Heuristics.Limits.Exceeded.MaxFileSize FOUND\nScanned files: 1\n", timedOut: false, cancelled: false, mapping: mapping)
        suite.expect(limit.incomplete && limit.findings.isEmpty, "limit alerts are incomplete coverage, never malware findings")
        for (status, timeout, cancelled) in [(Int32(2), false, false), (0, true, false), (0, false, true)] {
            suite.expect(ClamAVSupport.parse(status: status, output: "", timedOut: timeout, cancelled: cancelled, mapping: mapping).incomplete, "failure, timeout and cancellation cannot become a no-match completion")
        }
        suite.expect(!ClamAVSupport.fresh(nil) && !ClamAVSupport.fresh(Date().addingTimeInterval(-8 * 86_400)), "missing and stale definitions fail freshness")
        let args = ClamAVSupport.arguments(database: URL(fileURLWithPath: "/data with spaces"), list: URL(fileURLWithPath: "/file list"), temporary: URL(fileURLWithPath: "/tmp/scan"), certificates: "/certs")
        suite.expect(args.contains("--official-db-only=yes") && args.contains("--follow-file-symlinks=0") && !args.contains(where: { $0.hasPrefix("--remove") || $0.hasPrefix("--move=") }), "CLI arguments retain signature and symlink protections without any removal action")
    }

    private static func locales(_ suite: TestSuite) {
        for language in AppLanguage.allCases {
            suite.expect(StorageInspectionStrings.values[language]?.count == StorageInspectionStrings.Key.allCases.count, "every cleanup string exists for \(language.rawValue)")
            suite.expect(StorageInspectionStrings.values[language]?.allSatisfy { !$0.isEmpty } == true, "cleanup copy is nonempty for \(language.rawValue)")
        }
        suite.expect(SettingsBackupSupport.valueLooksRight(DefaultsKey.storageLargeMegabytes, 100)
            && !SettingsBackupSupport.valueLooksRight(DefaultsKey.storageLargeMegabytes, -1), "portable thresholds reject invalid restored values")
    }

    private static func fixtureSafety(_ suite: TestSuite, root: URL) throws {
        let folder = root.appendingPathComponent("FixtureSafety")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        suite.expect(try CleanupFixturePolicy.needsPreparation(folder), "an empty fixture folder is accepted")
        let retained = folder.appendingPathComponent("Keep.txt")
        try Data("do not overwrite".utf8).write(to: retained)
        suite.expect((try? CleanupFixturePolicy.needsPreparation(folder)) == nil, "nonempty folders cannot silently become fixtures")
        suite.expect(try String(contentsOf: retained, encoding: .utf8) == "do not overwrite", "fixture refusal preserves existing content")
        try CleanupFixturePolicy.marker(folder).write(to: folder.appendingPathComponent("fixture.prepared"))
        suite.expect(try !CleanupFixturePolicy.needsPreparation(folder), "verified fixture marker permits reuse without reseeding")
    }

    private static func actualEngine(_ suite: TestSuite, root: URL) throws {
        guard let source = ProcessInfo.processInfo.environment["ASTER_CLAMAV_TEST_DATABASE"], let tools = ClamAVTools.detect() else { return }
        let backendRoot = root.appendingPathComponent("Engine")
        try FileManager.default.createDirectory(at: backendRoot, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: source), to: backendRoot.appendingPathComponent("Definitions"))
        let chosen = root.appendingPathComponent("AVFixtures")
        try FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: true)
        try Data("Harmless Aster fixture.\n".utf8).write(to: chosen.appendingPathComponent("benign.txt"))
        let eicar = "X5O!P%@AP[4\\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*"
        try Data(eicar.utf8).write(to: chosen.appendingPathComponent("eicar.txt"))
        let files = StorageFolderScanner.scan(roots: [chosen], cancellation: .init()).files
        let backend = ClamAVBackend(tools: tools, root: backendRoot)
        try backend.verify(.init())
        _ = try backend.update(.init())
        suite.expect(ClamAVSupport.fresh(backend.definitionDate()), "real one-shot definition update preserves verified current definitions")
        let result = backend.scan(files, cancellation: .init(), processCancellation: .init())
        suite.expect(!result.failed && result.findings.count == 1 && result.findings[0].path.hasSuffix("eicar.txt"), "real optional ClamAV finds standardized EICAR and does not match the benign generated file")
        suite.expect(FileManager.default.fileExists(atPath: chosen.appendingPathComponent("eicar.txt").path), "real scanner never removes originals")
        print("Real ClamAV fixture: \(result.scanned) files, \(result.findings.count) EICAR match, incomplete=\(result.incomplete)")
    }

    private static func snapshotRecovery(_ suite: TestSuite, root: URL) throws {
        let directory = root.appendingPathComponent("Snapshots")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let interrupted = try ClamAVSnapshots.create(in: directory)
        try Data("generated scan copy".utf8).write(to: interrupted.appendingPathComponent("000.scan"))
        let unowned = directory.appendingPathComponent("Scan-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: unowned, withIntermediateDirectories: true)
        try ClamAVSnapshots.discardInterrupted(in: directory)
        suite.expect(!FileManager.default.fileExists(atPath: interrupted.path), "interrupted marked private snapshots are discarded before the next explicit scan")
        suite.expect(FileManager.default.fileExists(atPath: unowned.path), "snapshot cleanup preserves unmarked directories")
    }

    private static func signatureResults(_ suite: TestSuite, file: URL) {
        for (status, output, timeout, expected) in [
            (Int32(0), "", false, SecurityInspectionRow.Signature.valid),
            (1, "code object is not signed at all", false, .unsigned),
            (1, "a sealed resource is missing or invalid", false, .invalid),
            (1, "Permission denied", false, .unknown),
            (0, "", true, .unknown)
        ] {
            let row = SecurityInspector.signature(file) { path, arguments, seconds, _ in
                suite.expect(path == "/usr/bin/codesign" && seconds <= 8 && !arguments.contains("--sign"), "signature evidence uses only bounded read-only codesign actions")
                return .init(status: status, output: Data(output.utf8), timedOut: timeout)
            }
            suite.expect(row.signature == expected, "signature validity, unsigned, denied and timeout remain distinct")
        }
        let cancellation = BoundedProcessCancellation(); cancellation.cancel()
        let cancelled = SecurityInspector.signature(file, cancellation: cancellation) { _, _, _, _ in
            suite.expect(false, "cancelled security check must not launch a process")
            return .init(status: 0, output: Data(), timedOut: false)
        }
        suite.expect(cancelled.signature == .unknown, "cancelled signature check remains unknown")
    }

    private static func engineGates(_ suite: TestSuite, root: URL, files: [StorageFileSnapshot]) throws {
        let tools = ClamAVTools(scanner: "/fixture/clamscan", updater: "/fixture/freshclam", verifier: "/fixture/sigtool", certificates: "/fixture/certs")
        var calls: [String] = []
        let backend = ClamAVBackend(tools: tools, root: root.appendingPathComponent("EngineGates")) { path, _, _, _ in
            calls.append(path)
            return .init(status: 1, output: Data("fixture verification refused".utf8), timedOut: false)
        }
        let missing = backend.scan(files, cancellation: .init(), processCancellation: .init())
        suite.expect(missing.failed && missing.incomplete && calls.isEmpty, "missing definitions refuse a scan before launching any engine process")
        let stale = Int(Date().addingTimeInterval(-8 * 86_400).timeIntervalSince1970)
        for name in ["main", "daily", "bytecode"] {
            try Data("ClamAV-VDB:fixture:\(stale)".utf8).write(to: backend.database.appendingPathComponent(name + ".cvd"))
        }
        let old = backend.scan(files, cancellation: .init(), processCancellation: .init())
        suite.expect(old.failed && old.incomplete && calls.isEmpty, "stale definitions cannot produce an engine no-match result")
        try Data("ClamAV-VDB:fixture:\(Int(Date().timeIntervalSince1970))".utf8).write(to: backend.database.appendingPathComponent("daily.cvd"))
        let invalid = backend.scan(files, cancellation: .init(), processCancellation: .init())
        suite.expect(invalid.failed && calls == [tools.verifier], "signature refusal stops before clamscan even with a fresh header")
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import Foundation

enum ClamAVDefinitionUpdateTests {
    static func run(_ suite: TestSuite) {
        do {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("AsterDefinitionUpdate-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            try failedUpdates(suite, root: root)
            try recovery(suite, root: root)
            try publicationRollback(suite, root: root)
        } catch { suite.expect(false, "definition update checks failed: \(error)") }
    }

    private static func failedUpdates(_ suite: TestSuite, root: URL) throws {
        for mode in ["download", "verify", "cancel"] {
            let fixture = DefinitionUpdateFixture(root: root.appendingPathComponent(mode), mode: mode)
            let old = try fixture.prepare()
            suite.expect((try? fixture.backend.update(fixture.cancellation)) == nil, "failed \(mode) update remains an error")
            suite.expect(try Data(contentsOf: fixture.backend.database.appendingPathComponent("daily.cld")) == old,
                         "failed \(mode) update preserves the previous definitions byte for byte")
            let files = try FileManager.default.contentsOfDirectory(atPath: fixture.root.path)
            suite.expect(!files.contains(where: { $0.hasPrefix("Update-") }), "failed \(mode) update removes only its temporary download")
        }
    }

    private static func recovery(_ suite: TestSuite, root: URL) throws {
        let fixture = DefinitionUpdateFixture(root: root.appendingPathComponent("recovery"), mode: "success")
        _ = try fixture.prepare()
        _ = try fixture.backend.update(fixture.cancellation)
        suite.expect(!FileManager.default.fileExists(atPath: fixture.backend.database.appendingPathComponent("daily.cld").path),
                     "recovery replaces an unverifiable patched database with a verified complete download")
        suite.expect(ClamAVSupport.fresh(fixture.backend.definitionDate()) && fixture.downloadUsedFullCVD,
                     "recovering updates request complete official CVDs and retain freshness checks")
        suite.expect(fixture.verifiedNames == Set(["main.cvd", "daily.cvd", "bytecode.cvd"]),
                     "all three staged databases must verify before publication")
    }

    private static func publicationRollback(_ suite: TestSuite, root: URL) throws {
        let fixture = DefinitionUpdateFixture(root: root.appendingPathComponent("rollback"), mode: "success")
        let old = try fixture.prepare()
        suite.expect((try? fixture.backend.publishDefinitions(from: root.appendingPathComponent("missing"))) == nil,
                     "failed directory publication reports failure")
        suite.expect(try Data(contentsOf: fixture.backend.database.appendingPathComponent("daily.cld")) == old,
                     "failed directory promotion rolls the previous definitions back")
    }
}

private final class DefinitionUpdateFixture {
    let root: URL
    let mode: String
    let cancellation = BoundedProcessCancellation()
    var verifiedNames: Set<String> = []
    var downloadUsedFullCVD = false
    lazy var backend = ClamAVBackend(tools: .init(scanner: "/fixture/scanner", updater: "/fixture/updater",
        verifier: "/fixture/verifier", certificates: "/fixture/certs"), root: root) { [self] path, args, _, _ in
        if path == "/fixture/verifier" {
            verifiedNames.insert(URL(fileURLWithPath: args.last!).lastPathComponent)
            return .init(status: mode == "verify" ? 1 : 0, output: Data(), timedOut: false)
        }
        do { try download(args) } catch { return .init(status: 1, output: Data(), timedOut: false) }
        if mode == "cancel" { cancellation.cancel() }
        return .init(status: mode == "download" ? 1 : 0, output: Data(), timedOut: false)
    }

    init(root: URL, mode: String) { self.root = root; self.mode = mode }

    func prepare() throws -> Data {
        try FileManager.default.createDirectory(at: backend.database, withIntermediateDirectories: true)
        let old = Data("previous generated database".utf8)
        try old.write(to: backend.database.appendingPathComponent("daily.cld"))
        return old
    }

    private func download(_ args: [String]) throws {
        let config = args.first { $0.hasPrefix("--config-file=") }!.dropFirst("--config-file=".count)
        let text = try String(contentsOfFile: String(config), encoding: .utf8)
        downloadUsedFullCVD = text.contains("ScriptedUpdates no")
        let line = text.components(separatedBy: "\n")[0]
        let folder = URL(fileURLWithPath: String(line.dropFirst("DatabaseDirectory \"".count).dropLast()))
        let date = Int(Date().timeIntervalSince1970)
        for name in ["main", "daily", "bytecode"] {
            try Data("ClamAV-VDB:fixture:\(date)".utf8).write(to: folder.appendingPathComponent(name + ".cvd"))
        }
    }
}

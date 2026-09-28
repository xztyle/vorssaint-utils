// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Foundation

final class StorageInspectionService: ObservableObject {
    static let shared = StorageInspectionService()
    @Published var roots: [URL] = []
    @Published var result = StorageScanResult()
    @Published var duplicates = StorageDuplicateResult()
    @Published var selection = Set<String>()
    @Published var receipts: [StorageTrashReceipt] = []
    @Published var securityRows: [SecurityInspectionRow] = []
    @Published var securityPartial = false
    @Published var malware: ClamAVScanResult?
    @Published var hasScanned = false
    @Published var busy = false
    @Published var progress = 0
    @Published var detail = ""
    @Published var engineVersion = ""
    @Published var definitionDate: Date?
    @Published var definitionsVerified = false
    @Published var engineAvailable = false
    private var generation = UUID()
    private var cancellation = CleanerSupport.ScanCancellation()
    private var processCancellation = BoundedProcessCancellation()
    private var terminationObserver: NSObjectProtocol?
    private let queue = DispatchQueue(label: "io.github.xztyle.Aster.storage-inspection", qos: .utility)
    private var availability: Bool { CleanupProbe.root != nil || AppFeature.cleaner.isAvailable }
    var selectedFiles: [StorageFileSnapshot] { result.files.filter { selection.contains($0.id) } }
    var selectedBytes: Int64 { selectedFiles.reduce(0) { $0 + $1.allocatedBytes } }

    private init() {
        terminationObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main) { [weak self] _ in self?.stop() }
    }

    deinit {
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
    }

    func chooseFolders() {
        guard availability, !busy, CleanupProbe.root == nil else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        roots = Array(panel.urls.prefix(8)).map { (try? StorageLocalAccess.canonicalRoot($0)) ?? $0 }
        result = .init(); duplicates = .init(); selection = []; hasScanned = false
    }

    func scan() {
        guard !roots.isEmpty else { return }
        let roots = roots
        work({ [weak self] cancellation, _ in
            var last = Date.distantPast
            return StorageFolderScanner.scan(roots: roots, cancellation: cancellation) { count in
                guard Date().timeIntervalSince(last) > 0.1 else { return }
                last = Date()
                DispatchQueue.main.async { if !cancellation.isCancelled { self?.progress = count } }
            }
        }) { [weak self] value in
            self?.hasScanned = true
            self?.result = value
            self?.selection = []
            self?.duplicates = .init()
        }
    }

    func findDuplicates() {
        let files = result.files
        work({ cancellation, _ in StorageDuplicateFinder.find(files, cancellation: cancellation) }) { [weak self] value in
            self?.duplicates = value
            self?.selection = []
        }
    }

    func select(_ file: StorageFileSnapshot, included: Bool) {
        guard !busy else { return }
        if included, selection.count < 500 { selection.insert(file.id) } else { selection.remove(file.id) }
    }

    func keep(_ file: StorageFileSnapshot, group: UUID) {
        guard let index = duplicates.groups.firstIndex(where: { $0.id == group }) else { return }
        duplicates.groups[index].keeperID = file.id
        selection.remove(file.id)
    }

    func trashSelected() {
        let files = selectedFiles
        let groups = duplicates.groups
        guard !files.isEmpty, StorageInspectionPolicy.removalsAllowed(selection, groups: groups) else { return }
        work({ cancellation, _ in StorageTrashService.move(files, groups: groups, cancellation: cancellation) }) { [weak self] receipts in
            guard let self else { return }
            self.receipts += receipts
            let moved = Set(receipts.filter { $0.trash != nil }.map { $0.original.path })
            self.result.files.removeAll { moved.contains($0.id) }
            self.selection.subtract(moved)
            for file in files where moved.contains(file.id) {
                for path in self.result.folders.keys where StorageInspectionPolicy.isWithin(file.url, root: URL(fileURLWithPath: path)) {
                    self.result.folders[path]?.bytes -= file.allocatedBytes
                    self.result.folders[path]?.files -= 1
                }
            }
            self.duplicates.groups.removeAll { $0.files.contains { moved.contains($0.id) } }
        }
    }

    func inspectApplications() {
        guard availability, CleanupProbe.root == nil else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true; panel.allowedContentTypes = [.applicationBundle]
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        work({ _, cancellation in SecurityInspector.inspectApps(urls, cancellation: cancellation) }) { [weak self] rows in self?.securityRows = rows.rows; self?.securityPartial = rows.partial }
    }

    func inspectStartup() {
        let paths = CleanupProbe.root.map { [$0.appendingPathComponent("LaunchAgents")] } ?? [
            URL(fileURLWithPath: NSHomeDirectory() + "/Library/LaunchAgents"),
            URL(fileURLWithPath: "/Library/LaunchAgents"), URL(fileURLWithPath: "/Library/LaunchDaemons")]
        work({ cancellation, process in SecurityInspector.startupEntries(roots: paths, cancellation: cancellation, processCancellation: process) }) { [weak self] rows in self?.securityRows = rows.rows; self?.securityPartial = rows.partial }
    }

    func refreshEngine() {
        work({ _, cancellation -> (String, Date?, Bool) in
            guard let backend = self.backend() else { return ("", nil, false) }
            let version = backend.run(backend.tools.scanner, ["--version"], 10, cancellation)
            let text = version.status == 0 ? String(decoding: version.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) : ""
            return (text, backend.definitionDate(), (try? backend.verify(cancellation)) != nil)
        }) { [weak self] value in
            self?.engineVersion = value.0; self?.definitionDate = value.1
            self?.definitionsVerified = value.2; self?.engineAvailable = !value.0.isEmpty
        }
    }

    func updateDefinitions() {
        work({ _, cancellation -> Result<String, Error> in
            guard let backend = self.backend() else { return .failure(StorageInspectionFailure.unavailable) }
            return Result { try backend.update(cancellation) }
        }) { [weak self] value in
            switch value {
            case .success(let detail): self?.detail = detail; self?.definitionDate = self?.backend()?.definitionDate(); self?.definitionsVerified = true
            case .failure(let error): self?.detail = error.localizedDescription; self?.definitionsVerified = false
            }
        }
    }

    func scanMalware() {
        let files = result.files
        let partial = result.isPartial
        guard !files.isEmpty else { return }
        work({ cancellation, process -> ClamAVScanResult in
            guard let backend = self.backend() else { return .init(incomplete: true, failed: true) }
            var report = backend.scan(files, cancellation: cancellation, processCancellation: process)
            report.incomplete = report.incomplete || partial
            return report
        }) { [weak self] value in self?.malware = value }
    }

    func installEngine() {
        guard CleanupProbe.root == nil else { return }
        let brew = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }
        guard let brew else { detail = StorageInspectionStrings.current[.brewMissing]; return }
        work({ _, cancellation in
            BoundedProcessRunner.run(brew, ["install", "clamav"], timeout: 900, maxOutputBytes: 65_536,
                environment: HomebrewEnvironment.forBrew, cancellation: cancellation)
        }) { [weak self] result in
            self?.detail = String(decoding: result.output, as: UTF8.self)
            self?.engineAvailable = !result.timedOut && result.status == 0 && ClamAVTools.detect() != nil
        }
    }

    func cancel() {
        cancellation.cancel()
        processCancellation.cancel()
    }

    func stop() {
        cancel(); generation = UUID(); busy = false
        roots = []; result = .init(); duplicates = .init(); selection = []; hasScanned = false
        securityRows = []; malware = nil; detail = ""
    }

    private func backend() -> ClamAVBackend? {
        guard let tools = ClamAVTools.detect() else { return nil }
        let base = CleanupProbe.root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "io.github.xztyle.Aster", isDirectory: true)
        return ClamAVBackend(tools: tools, root: base.appendingPathComponent("MalwareScan", isDirectory: true))
    }

    private func work<T>(_ action: @escaping (CleanerSupport.ScanCancellation, BoundedProcessCancellation) -> T,
                         completion: @escaping (T) -> Void) {
        guard availability, !busy else { return }
        busy = true; detail = ""; progress = 0
        let token = UUID(); generation = token
        let cancellation = CleanerSupport.ScanCancellation()
        let process = BoundedProcessCancellation()
        self.cancellation = cancellation; processCancellation = process
        queue.async { [weak self] in
            let value = action(cancellation, process)
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                self.busy = false
                completion(value)
            }
        }
    }
}

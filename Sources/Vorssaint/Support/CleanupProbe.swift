// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import SwiftUI

/// Explicit generated-only acceptance profile. No ordinary delegate, scheduler,
/// engine install, permissions request or automatic scan is started here.
enum CleanupProbe {
    static var root: URL? {
        guard let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--cleanup-fixture=") }) else { return nil }
        let supplied = URL(fileURLWithPath: String(argument.dropFirst("--cleanup-fixture=".count)), isDirectory: true)
        return (try? StorageLocalAccess.canonicalRoot(supplied)) ?? supplied
    }
    private static var window: NSWindow?
    private static var resizeObserver: NSObjectProtocol?
    private static var resultObserver: AnyCancellable?
    private static var resultWritePending = false

    static func runIfRequested() {
        guard let root else { return }
        do { try prepare(root) }
        catch { fputs("Cleanup fixture failed: \(error.localizedDescription)\n", stderr); exit(1) }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        StorageInspectionService.shared.roots = [root.appendingPathComponent("Files", isDirectory: true)]
        observeResults()
        let window = makeWindow()
        self.window = window
        resizeObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification,
            object: window, queue: .main) { _ in writeGeometry() }
        window.center(); window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { writeGeometry() }
        app.activate(ignoringOtherApps: true)
        app.run()
        exit(0)
    }

    private static func observeResults() {
        resultObserver = StorageInspectionService.shared.objectWillChange.sink {
            guard !resultWritePending else { return }
            resultWritePending = true
            DispatchQueue.main.async {
                resultWritePending = false
                writeResults()
            }
        }
        writeResults()
    }

    private static func writeResults() {
        guard let root else { return }
        let service = StorageInspectionService.shared
        let filesRoot = root.appendingPathComponent("Files", isDirectory: true)
        guard service.roots == [filesRoot], (try? CleanupFixturePolicy.needsPreparation(root)) == false else { return }
        do {
            let data = try CleanupFixtureReceipt.data(root: filesRoot, scan: service.result,
                duplicates: service.duplicates, receipts: service.receipts, selection: service.selection,
                malware: service.malware, busy: service.busy)
            guard PrivateFileStore.write(data, to: root.appendingPathComponent("action-state.json")) else {
                throw StorageInspectionFailure.failed
            }
        } catch { fputs("Cleanup fixture receipt failed: \(error)\n", stderr) }
    }

    private static func makeWindow() -> NSWindow {
        let size = NSSize(width: 1060, height: 780)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Aster — " + StorageInspectionStrings.current[.title]
        let host = NSHostingController(rootView: StorageInspectionView())
        host.sizingOptions = []
        host.view.frame = NSRect(origin: .zero, size: size)
        host.view.autoresizingMask = [.width, .height]
        window.contentViewController = host
        window.setContentSize(size)
        window.contentMinSize = NSSize(width: 860, height: 600)
        return window
    }

    private static func writeGeometry() {
        guard let root, let window else { return }
        let frame = window.frame
        let content = window.contentView?.bounds ?? .zero
        let state: [String: Any] = ["pid": ProcessInfo.processInfo.processIdentifier,
            "frame": [frame.minX, frame.minY, frame.width, frame.height],
            "content": [content.width, content.height], "visible": window.isVisible,
            "minimumContent": [window.contentMinSize.width, window.contentMinSize.height]]
        guard let data = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]) else { return }
        PrivateFileStore.write(data, to: root.appendingPathComponent("ui-state.json"))
    }

    private static func prepare(_ root: URL) throws {
        guard try CleanupFixturePolicy.needsPreparation(root) else { return }
        let files = root.appendingPathComponent("Files", isDirectory: true)
        guard PrivateFileStore.createDirectory(at: files, container: root) else { throw StorageInspectionFailure.failed }
        let content = Data("Aster generated duplicate fixture.\n".utf8)
        for name in ["Original.txt", "Duplicate.txt"] { guard PrivateFileStore.write(content, to: files.appendingPathComponent(name)) else { throw StorageInspectionFailure.failed } }
        PrivateFileStore.write(Data("Different generated content.\n".utf8), to: files.appendingPathComponent("Keep.txt"))
        PrivateFileStore.write(Data(repeating: 65, count: 8 * 1_048_576), to: files.appendingPathComponent("Large fixture.bin"))
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-400 * 86_400)], ofItemAtPath: files.appendingPathComponent("Keep.txt").path)
        try FileManager.default.createSymbolicLink(at: files.appendingPathComponent("Link"), withDestinationURL: files.appendingPathComponent("Original.txt"))
        let package = files.appendingPathComponent("Example.app", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        PrivateFileStore.write(CleanupFixturePolicy.marker(try StorageLocalAccess.canonicalRoot(root)), to: root.appendingPathComponent("fixture.prepared"))
    }
}

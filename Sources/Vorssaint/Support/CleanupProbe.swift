// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
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

    static func runIfRequested() {
        guard let root else { return }
        do { try prepare(root) }
        catch { fputs("Cleanup fixture failed: \(error.localizedDescription)\n", stderr); exit(1) }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        StorageInspectionService.shared.roots = [root.appendingPathComponent("Files", isDirectory: true)]
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 780),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Aster — " + StorageInspectionStrings.current[.title]
        let host = NSHostingController(rootView: StorageInspectionView())
        host.sizingOptions = []
        window.contentViewController = host
        window.center(); window.makeKeyAndOrderFront(nil)
        self.window = window
        app.activate(ignoringOtherApps: true)
        app.run()
        exit(0)
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

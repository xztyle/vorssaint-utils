// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

/// An explicit disposable profile for visual acceptance. This route starts no
/// app delegate, capture timer, permission request, or other background utility.
enum ClipboardLibraryProbe {
    static var root: URL? {
        guard let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--clipboard-fixture=") }) else { return nil }
        return URL(fileURLWithPath: String(argument.dropFirst("--clipboard-fixture=".count)), isDirectory: true)
    }
    private static var subscription: AnyCancellable?
    private static var stateSubscription: AnyCancellable?

    static func runIfRequested() {
        guard let root else { return }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        do { try prepare(root) }
        catch { fputs("Clipboard fixture failed: \(error.localizedDescription)\n", stderr); exit(1) }
        let history = ClipboardHistoryService.shared
        stateSubscription = history.$quickQuery.combineLatest(history.$quickResults).sink { _, _ in
            DispatchQueue.main.async { recordState() }
        }
        subscription = history.$libraryReady.filter { $0 }.first().sink { _ in
            DispatchQueue.main.async {
                history.showHistoryWindow(preferNotch: false)
                app.activate(ignoringOtherApps: true)
            }
        }
        app.run()
        history.flushBeforeTermination()
        exit(0)
    }

    static func recordState() {
        guard let root, let panel = ClipboardHistoryService.shared.panel else { return }
        let history = ClipboardHistoryService.shared
        let screen = panel.screen ?? NSScreen.withMouse ?? NSScreen.main
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("io.github.xztyle.Aster.clipboard-fixture"))
        let state: [String: Any] = [
            "frame": rect(panel.frame), "screenFrame": rect(screen?.frame ?? .zero),
            "visibleFrame": rect(screen?.visibleFrame ?? .zero),
            "targetFrame": rect(ClipboardHistoryWindowSizing.frame(on: screen?.frame ?? .zero)),
            "level": panel.level.rawValue, "dockLevel": CGWindowLevelForKey(.dockWindow),
            "visible": panel.isVisible, "presented": history.drawerPresentation.isPresented,
            "preview": history.quickPreviewPresented, "query": history.quickQuery,
            "resultCount": history.quickResults.count, "fixtureTypes": pasteboard.types?.map(\.rawValue) ?? []
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]) else { return }
        PrivateFileStore.write(data, to: root.appendingPathComponent("ui-state.json"))
    }

    private static func rect(_ value: NSRect) -> [String: Double] {
        ["x": value.minX, "y": value.minY, "width": value.width, "height": value.height]
    }

    private static func prepare(_ root: URL) throws {
        let store = try ClipboardLibraryStore(root: root)
        let marker = root.appendingPathComponent("fixture.prepared")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        guard try store.load().entries.isEmpty else { return }
        let assetRoot = root.appendingPathComponent("ClipboardImages")
        PrivateFileStore.createDirectory(at: assetRoot, container: root)
        var entries = try sampleEntries(assetRoot: assetRoot)
        if let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--clipboard-fixture-count=") }),
           let count = Int(argument.split(separator: "=").last ?? ""), count > entries.count {
            entries += (entries.count..<min(count, 50_000)).map { index in
                ClipboardHistoryEntry(text: "Generated research note \(index): café 日本語 library search",
                    copiedAt: Date().addingTimeInterval(-Double(index) * 600))
            }
        }
        var board = ClipboardCollection(name: "Design notes", color: 1)
        board.entryIDs = [entries[2].id, entries[0].id]
        for index in [0, 2] { entries[index].collectionIDs = [board.id]; entries[index].pinnedAt = Date() }
        try store.save(.init(entries: entries, collections: [board, ClipboardCollection(name: "Research", color: 4)]))
        guard PrivateFileStore.write(Data(), to: marker) else { throw ClipboardLibraryError.invalidArchive }
    }

    private static func sampleEntries(assetRoot: URL) throws -> [ClipboardHistoryEntry] {
        var note = ClipboardHistoryEntry(text: "A small, thoughtful library.\n\nFind a phrase from last week. Keep what matters in a collection.\n\nThe original stays available when you edit a copy.")
        note.title = "A place for useful things"
        note.sourceApp = "Fixture Notes"
        var rich = ClipboardHistoryEntry(text: "Rich text keeps its formatting.")
        rich.title = "Formatted selection"
        let formatted = NSAttributedString(string: rich.text, attributes: [.font: NSFont.boldSystemFont(ofSize: 20), .foregroundColor: NSColor.systemPurple])
        let rtf = try formatted.data(from: NSRange(location: 0, length: formatted.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        PrivateFileStore.write(rtf, to: assetRoot.appendingPathComponent("fixture.rtf"))
        rich.representations[NSPasteboard.PasteboardType.rtf.rawValue] = "fixture.rtf"
        let image = try sampleImage(assetRoot)
        let file = assetRoot.deletingLastPathComponent().appendingPathComponent("FixtureReadme.txt")
        PrivateFileStore.write(Data("Generated Aster fixture file.\n".utf8), to: file)
        let values = [note, image, ClipboardHistoryEntry(text: "https://developer.apple.com/design/"), rich,
                      ClipboardHistoryEntry(text: "#8B5CF6"), ClipboardHistoryEntry(text: "", kind: .files, filePaths: [file.path]),
                      ClipboardHistoryEntry(text: "", kind: .files, filePaths: [assetRoot.appendingPathComponent("missing.pdf").path])]
        return values.enumerated().map { index, value in
            var entry = value
            entry.copiedAt = Date().addingTimeInterval(-Double(index) * 420)
            entry.firstCopiedAt = entry.copiedAt
            return entry
        }
    }

    private static func sampleImage(_ root: URL) throws -> ClipboardHistoryEntry {
        let image = NSImage(size: NSSize(width: 900, height: 600))
        image.lockFocus()
        NSColor.windowBackgroundColor.setFill()
        NSRect(x: 0, y: 0, width: 900, height: 600).fill()
        for (index, color) in [NSColor.systemPurple, .systemTeal, .systemOrange].enumerated() {
            color.setFill()
            NSBezierPath(roundedRect: NSRect(x: 95 + index * 235, y: 155 + index * 35, width: 225, height: 225), xRadius: 55, yRadius: 55).fill()
        }
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]),
              PrivateFileStore.write(png, to: root.appendingPathComponent("fixture.png")) else { throw ClipboardLibraryError.invalidArchive }
        return ClipboardHistoryEntry(text: "", kind: .image, imageFile: "fixture.png",
                                     imageHash: ClipboardLibraryArchive.checksum(png), imageWidth: 900, imageHeight: 600)
    }
}

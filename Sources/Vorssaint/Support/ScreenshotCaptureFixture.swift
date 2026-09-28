// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Explicit UI acceptance mode. It never creates AppDelegate, capture services,
/// global hotkeys, or a pasteboard reader. All input images are generated here.
enum ScreenshotCaptureFixture {
    static func runIfRequestedAndExit() {
        let configured = Bundle.main.object(forInfoDictionaryKey: "AsterCaptureFixtureDirectory") as? String
        guard let path = requestedDirectory(arguments: CommandLine.arguments,
                                            bundleDirectory: configured) else { return }
        do {
            let directory = try fixtureDirectory(path)
            let app = NSApplication.shared
            let delegate = FixtureDelegate(directory: directory)
            app.delegate = delegate
            app.setActivationPolicy(.regular)
            withExtendedLifetime(delegate) { app.run() }
            exit(0)
        } catch {
            fputs("Capture fixture: \(error)\n", stderr)
            exit(2)
        }
    }

    private static func requestedDirectory(arguments: [String], bundleDirectory: String?) -> String? {
        if let argument = arguments.first(where: { $0.hasPrefix("--capture-fixture=") }) {
            return String(argument.dropFirst("--capture-fixture=".count))
        }
        return bundleDirectory.flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func fixtureDirectory(_ path: String) throws -> URL {
        guard path.hasPrefix("/"), path != "/" else { throw CocoaError(.fileWriteInvalidFileName) }
        let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        let resolved = canonicalDirectory(url)
        let roots = [canonicalDirectory(FileManager.default.temporaryDirectory).path,
                     canonicalDirectory(URL(fileURLWithPath: "/private/tmp")).path]
        guard roots.contains(where: { resolved.path.hasPrefix($0 + "/") }),
              (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    private static func canonicalDirectory(_ url: URL) -> URL {
        var ancestor = url.standardizedFileURL
        var suffix: [String] = []
        while !FileManager.default.fileExists(atPath: ancestor.path), ancestor.path != "/" {
            suffix.append(ancestor.lastPathComponent)
            ancestor.deleteLastPathComponent()
        }
        return suffix.reversed().reduce(ancestor.resolvingSymlinksInPath()) {
            $0.appendingPathComponent($1, isDirectory: true)
        }
    }

    private final class FixtureDelegate: NSObject, NSApplicationDelegate {
        let directory: URL
        let suiteName = "io.github.xztyle.Aster.capture-fixture.\(UUID().uuidString)"
        var workspace: ScreenshotCaptureWorkspace?
        var receiver: ScreenshotFixtureReceiver?
        var manifest: [[String: Any]] = []
        init(directory: URL) { self.directory = directory }

        func applicationDidFinishLaunching(_ notification: Notification) {
            guard let preferences = UserDefaults(suiteName: suiteName) else { NSApp.terminate(nil); return }
            preferences.register(defaults: Defaults.registeredDefaults)
            preferences.set(0, forKey: "screenshotPreviewLifetime")
            preferences.set(false, forKey: DefaultsKey.screenshotPreviewTakesFocus)
            preferences.set(false, forKey: DefaultsKey.screenshotSharingEnabled)
            preferences.set("bottomLeft", forKey: DefaultsKey.screenshotPreviewPosition)
            let workspace = ScreenshotCaptureWorkspace(preferences: preferences, fixtureDirectory: directory)
            workspace.output = { _, _, action in action == .discard ? [.discard] : [] }
            workspace.committed = { [weak self] id, capture, revision in
                self?.record(id: id, capture: capture, revision: revision)
            }
            self.workspace = workspace
            for index in 1...3 { addImage(index, workspace: workspace) }
            receiver = ScreenshotFixtureReceiver(workspace: workspace, directory: directory)
            receiver?.show()
        }

        func applicationWillTerminate(_ notification: Notification) {
            workspace?.closeAll()
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }

        private func addImage(_ number: Int, workspace: ScreenshotCaptureWorkspace) {
            guard let image = Self.image(number), let screen = NSScreen.main else { return }
            let capture = ScreenshotSelectionController.Capture(image: image, scale: 2,
                                                                 anchorRect: screen.frame)
            let id = workspace.add(capture)
            record(id: id, capture: capture, revision: 0)
        }

        private func record(id: UUID, capture: ScreenshotSelectionController.Capture, revision: Int) {
            let name = "\(id.uuidString)-r\(revision).png"
            guard let png = ScreenshotRenderer.pngData(from: capture.image, scale: capture.scale) else { return }
            do {
                try RecentCaptureStore.write(png, to: directory.appendingPathComponent(name))
                manifest.append(["id": id.uuidString, "revision": revision, "file": name,
                                 "width": capture.image.width, "height": capture.image.height])
                let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
                try RecentCaptureStore.write(data, to: directory.appendingPathComponent("manifest.json"))
            } catch { fputs("Capture fixture output failed: \(error)\n", stderr) }
        }

        private static func image(_ number: Int) -> CGImage? {
            let image = NSImage(size: NSSize(width: 900, height: 500))
            image.lockFocus()
            let colors: [NSColor] = [.systemBlue, .systemOrange, .systemTeal]
            colors[number - 1].setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: 900, height: 500)).fill()
            let text = "Capture \(number)\nEdit me, then choose Done"
            (text as NSString).draw(in: NSRect(x: 55, y: 190, width: 800, height: 150),
                                   withAttributes: [.font: NSFont.systemFont(ofSize: 40, weight: .bold),
                                                    .foregroundColor: NSColor.white])
            NSColor.white.setStroke()
            let box = NSBezierPath(rect: NSRect(x: 60, y: 55, width: 780, height: 80))
            box.lineWidth = 8
            box.stroke()
            image.unlockFocus()
            return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
    }
}

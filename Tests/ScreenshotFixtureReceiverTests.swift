// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Constructs the actual production subclass through its designated initializer.
/// No application window is created; the pasteboard is a private test-only board.
enum ScreenshotFixtureReceiverTests {
    static func run(_ suite: TestSuite) {
        fixtureEntrypoint(suite)
        fixturePaths(suite)
        rejectsTemporaryRootItself(suite)
        receiverImportsImage(suite)
    }

    private static func fixtureEntrypoint(_ suite: TestSuite) {
        let configured = "/private/tmp/aster-capture-configured"
        let argument = "/private/tmp/aster-capture-argument"
        suite.expect(requestedDirectory(arguments: ["Aster"], bundleDirectory: configured) == configured
                     && requestedDirectory(arguments: ["Aster", "--capture-fixture=\(argument)"],
                                           bundleDirectory: configured) == argument
                     && requestedDirectory(arguments: ["Aster"], bundleDirectory: nil) == nil,
                     "signed fixture bundle key launches early while an explicit argument takes precedence")
    }

    private static func fixturePaths(_ suite: TestSuite) {
        do {
            let root = try fixtureDirectory("/private/tmp/aster-fixture-root-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }
            suite.expect(FileManager.default.fileExists(atPath: root.path),
                         "private temporary roots accept Foundation's /private/tmp normalization")
            let reopened = try fixtureDirectory(root.path)
            suite.expect(FileManager.default.fileExists(atPath: reopened.path),
                         "an existing private fixture root resolves consistently")
        } catch { suite.expect(false, "fixture temporary root: \(error)") }
    }

    private static func rejectsTemporaryRootItself(_ suite: TestSuite) {
        do {
            _ = try fixtureDirectory("/private/tmp")
            suite.expect(false, "the shared temporary root is never a fixture directory")
        } catch { suite.expect(true, "the shared temporary root is never a fixture directory") }
        do {
            _ = try fixtureDirectory("relative-capture-root")
            suite.expect(false, "fixture root must be an absolute path")
        } catch { suite.expect(true, "fixture root must be an absolute path") }
    }

    private static func receiverImportsImage(_ suite: TestSuite) {
        let view = DropTextView(frame: CGRect(x: 0, y: 0, width: 590, height: 430), textContainer: nil)
        suite.expect(view.window == nil && view.isRichText && view.importsGraphics
                     && view.textStorage != nil && view.layoutManager != nil,
                     "fixture text receiver constructs safely without a window")
        guard let image = ScreenshotContinuityTests.baseImage(),
              let png = ScreenshotRenderer.pngData(from: image, scale: 2),
              let tiff = ScreenshotRenderer.tiffData(from: image, scale: 2) else { return }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.declareTypes([.png, .tiff], owner: nil)
        board.setData(png, forType: .png)
        board.setData(tiff, forType: .tiff)
        let imported = view.importImage(from: board)
        var attachments = 0
        view.textStorage?.enumerateAttribute(.attachment, in: NSRange(location: 0, length: view.textStorage?.length ?? 0)) {
            value, _, _ in if value is NSTextAttachment { attachments += 1 }
        }
        suite.expect(imported && attachments == 1,
                     "AppKit imports a real image representation as an attachment in the fixture text input")
    }
}

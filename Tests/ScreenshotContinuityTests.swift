// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Exercises the production renderer and drag formats without any global pasteboard.
enum ScreenshotContinuityTests {
    static func run(_ suite: TestSuite) {
        policy(suite)
        transfer(suite)
    }

    private static func policy(_ suite: TestSuite) {
        suite.expect(ScreenshotPreviewLifetime.duration(0) == 0
                     && ScreenshotPreviewLifetime.duration(-1) == 30,
                     "keep-open is explicit and invalid lifetime values have a predictable fallback")
        let items = (0..<8).map { ($0, UUID()) }
        let victims = ScreenshotPreviewPolicy.evictionCandidates(items: items.map {
            (id: $0.1, bytes: 10, active: $0.0 < 2)
        })
        suite.expect(victims == [items[2].1, items[3].1],
                     "six preview limit evicts the oldest inactive captures, never the editor or drag")
        suite.expect(ScreenshotPreviewPolicy.evictionCandidates(items: [
            (id: UUID(), bytes: ScreenshotPreviewPolicy.maximumBytes + 1, active: false)
        ]).isEmpty, "a single large scrolling capture remains available")
        let visible = CGRect(x: -1600, y: 40, width: 1500, height: 800)
        let base = CGRect(x: -1588, y: 52, width: 350, height: 210)
        let frames = (0..<6).map {
            ScreenshotPreviewPolicy.stackFrame(base: base, visible: visible, index: $0, top: false, right: false)
        }
        suite.expect(frames.allSatisfy(visible.contains), "every stacked preview stays on its capture display")
        suite.expect(frames.enumerated().allSatisfy { index, rect in
            frames.dropFirst(index + 1).allSatisfy { !rect.intersects($0) }
        }, "six previews use separate rows and columns without overlapping")
        suite.expect(SettingsBackupSupport.exportKeys().contains("screenshotPreviewLifetime"),
                     "preview lifetime participates in settings backup")
        let wide = ScreenshotPreviewPolicy.imageSize(CGSize(width: 1600, height: 400))
        let thin = ScreenshotPreviewPolicy.floatingSize(image: CGSize(width: 30, height: 300))
        suite.expect(wide == CGSize(width: 320, height: 80)
                     && thin.width >= 116 && thin.height >= 44,
                     "the floating preview preserves image shape and keeps hover controls reachable")
        suite.expect(!ScreenshotPreviewPolicy.showsActions(hovered: false, menuTracking: false, dragging: false)
                     && ScreenshotPreviewPolicy.showsActions(hovered: true, menuTracking: false, dragging: false)
                     && ScreenshotPreviewPolicy.showsActions(hovered: false, menuTracking: true, dragging: false)
                     && !ScreenshotPreviewPolicy.showsActions(hovered: true, menuTracking: false, dragging: true),
                     "floating controls appear only during hover or menu use and hide during drag")
        dismissGesture(suite)
        for language in AppLanguage.allCases {
            let labels = FeatureStrings.screenshotPreview(language)
            suite.expect(!labels.lifetime.isEmpty && !labels.keepOpen.isEmpty && !labels.caption.isEmpty,
                         "preview lifetime is translated for \(language.rawValue)")
        }
    }

    private static func dismissGesture(_ suite: TestSuite) {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let gesture = ScreenshotPreviewSwipeGesture.self
        suite.expect(gesture.canTrack(deltaX: 10, deltaY: 1, inverted: true,
                                      precise: true, enabled: true)
                     && gesture.canTrack(deltaX: -10, deltaY: 1, inverted: false,
                                         precise: true, enabled: true)
                     && !gesture.canTrack(deltaX: 1, deltaY: 10, inverted: true,
                                          precise: true, enabled: true)
                     && !gesture.canTrack(deltaX: 10, deltaY: 0, inverted: true,
                                          precise: false, enabled: true),
                     "two-finger left swipe works with either scroll direction and ignores wheels")
        suite.expect(gesture.trackpadProgress(amount: 0.5, inverted: true) == 0.5
                     && gesture.trackpadProgress(amount: -0.5, inverted: false) == 0.5
                     && gesture.trackpadProgress(amount: -0.5, inverted: true) == 0,
                     "trackpad movement follows the physical leftward gesture")
        suite.expect(gesture.canBegin(dx: -8, dy: 1, sourceScreen: screen,
                                      otherScreens: [], y: 120),
                     "a horizontal left drag moves the card itself")
        suite.expect(!gesture.canBegin(dx: -8, dy: 12, sourceScreen: screen,
                                       otherScreens: [], y: 120)
                     && !gesture.canBegin(dx: 20, dy: 0, sourceScreen: screen,
                                          otherScreens: [], y: 120),
                     "vertical and rightward drags remain native image transfers")
        suite.expect(gesture.shouldDismiss(dx: -122, dy: 1, width: 320,
                                           startX: 230, screenMinX: 0, cancelled: false)
                     && !gesture.shouldDismiss(dx: -80, dy: 1, width: 320,
                                               startX: 230, screenMinX: 0, cancelled: false)
                     && !gesture.shouldDismiss(dx: -122, dy: 1, width: 320,
                                               startX: 230, screenMinX: 0, cancelled: true),
                     "a full swipe exits; a short or cancelled swipe springs back")
        suite.expect(gesture.shouldDismiss(dx: -25, dy: 0, width: 320,
                                           startX: 45, screenMinX: 0, cancelled: false)
                     && !gesture.shouldDismiss(dx: -25, dy: 30, width: 320,
                                               startX: 45, screenMinX: 0, cancelled: false),
                     "a swipe near the screen edge needs less travel but stays horizontal")
        suite.expect(gesture.exitX(screenMinX: screen.minX, width: 320) < screen.minX - 320,
                     "the exit animation carries the whole card beyond the screen edge")
        let leftDisplay = CGRect(x: -1280, y: 0, width: 1280, height: 800)
        suite.expect(!gesture.canBegin(dx: -8, dy: 0, sourceScreen: screen,
                                       otherScreens: [leftDisplay], y: 120),
                     "a display to the left remains a valid drag destination")
    }

    private static func transfer(_ suite: TestSuite) {
        guard let image = baseImage(), let cropped = image.cropping(to: CGRect(x: 10, y: 10, width: 100, height: 60)),
              let export = ScreenshotRenderer.renderExport(
                baseImage: cropped,
                annotations: [.init(tool: .redact, rect: CGRect(x: 10, y: 10, width: 25, height: 25), color: .black)],
                pixelated: [:], scale: 2, annotationShadowsEnabled: false,
                watermark: .init(), watermarkImage: nil, style: .init(kind: .none, cornerRadius: 0),
                fill: .none, downscaleTo1x: false) else { suite.expect(false, "render crop and redaction"); return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        guard let transfer = ScreenshotDragTransfer(image: export.image, scale: export.scale,
                                                    prefix: "Edited", directory: directory) else { return }
        let provider = transfer.itemProvider()
        suite.expect(provider.hasItemConformingToTypeIdentifier(UTType.png.identifier)
                     && provider.hasItemConformingToTypeIdentifier(UTType.tiff.identifier),
                     "corner drag offers actual PNG and TIFF image representations")
        verifyProvider(provider, expected: transfer.png, suite: suite)
        guard let item = transfer.pasteboardItem(), let url = item.string(forType: .fileURL).flatMap(URL.init(string:))
        else { suite.expect(false, "native drag payload"); return }
        suite.expect(item.data(forType: .png) == transfer.png && (try? Data(contentsOf: url)) == transfer.png,
                     "native image bytes and file URL contain exactly the same edited pixels")
        verifyImage(transfer.png, suite: suite)
    }

    private static func verifyProvider(_ provider: NSItemProvider, expected: Data, suite: TestSuite) {
        let dataReady = DispatchSemaphore(value: 0)
        var loaded: Data?
        provider.loadDataRepresentation(forTypeIdentifier: UTType.png.identifier) { data, _ in
            loaded = data; dataReady.signal()
        }
        suite.expect(dataReady.wait(timeout: .now() + 5) == .success && loaded == expected,
                     "a receiver loads the exact edited PNG bytes from the provider")
        let fileReady = DispatchSemaphore(value: 0)
        var fileData: Data?
        provider.loadFileRepresentation(forTypeIdentifier: UTType.png.identifier) { url, _ in
            fileData = url.flatMap { try? Data(contentsOf: $0) }; fileReady.signal()
        }
        suite.expect(fileReady.wait(timeout: .now() + 5) == .success && fileData == expected,
                     "a file receiver loads the same edited PNG representation")
    }

    private static func verifyImage(_ png: Data, suite: TestSuite) {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?
        else { suite.expect(false, "edited PNG decodes"); return }
        suite.expect(decoded.width == 100 && decoded.height == 60,
                     "drag output contains the crop, not the original dimensions")
        suite.expect((properties[kCGImagePropertyDPIWidth] as? NSNumber)?.intValue == 144,
                     "drag output preserves Retina density")
        guard let context = CGContext(data: nil, width: 100, height: 60, bitsPerComponent: 8,
                                      bytesPerRow: 400, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.draw(decoded, in: CGRect(x: 0, y: 0, width: 100, height: 60))
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        let blackPixels = (0..<6000).filter { bytes[$0 * 4] < 40 && bytes[$0 * 4 + 1] < 40 && bytes[$0 * 4 + 2] < 40 }
        suite.expect(blackPixels.count >= 400, "drag output contains the visible redaction pixels")
    }

    static func baseImage() -> CGImage? {
        guard let context = CGContext(data: nil, width: 160, height: 100, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 0.8, blue: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 160, height: 100))
        return context.makeImage()
    }
}

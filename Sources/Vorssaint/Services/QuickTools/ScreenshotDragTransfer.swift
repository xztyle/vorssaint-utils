// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The byte and file representations are made from the same committed export.
/// Provider callbacks retain the bytes and can recreate a file for late readers.
struct ScreenshotDragTransfer {
    let png: Data
    let tiff: Data?
    let name: String
    let directory: URL?

    init?(image: CGImage, scale: CGFloat, prefix: String, directory: URL? = nil) {
        guard let png = ScreenshotRenderer.pngData(from: image, scale: scale) else { return nil }
        self.directory = directory
        self.png = png
        tiff = ScreenshotRenderer.tiffData(from: image, scale: scale)
        name = ScreenshotSupport.fileName(prefix: prefix, date: Date())
    }

    static var temporaryDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "io.github.xztyle.Aster", isDirectory: true)
            .appendingPathComponent("CaptureTransfers", isDirectory: true)
    }

    static func removeExpiredFiles(now: Date = Date()) {
        let root = temporaryDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.creationDateKey, .isSymbolicLinkKey]),
              (try? root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { return }
        for file in files where file.lastPathComponent.hasPrefix("ScreenshotDrag-") {
            guard let values = try? file.resourceValues(forKeys: [.creationDateKey, .isSymbolicLinkKey]),
                  values.isSymbolicLink != true, let date = values.creationDate,
                  now.timeIntervalSince(date) > 48 * 3600 else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    func file() -> URL? {
        guard let url = try? ScreenshotSupport.temporaryDragFile(
            data: png, name: name, directory: directory ?? Self.temporaryDirectory) else { return nil }
        try? FileManager.default.setAttributes([.posixPermissions: 0o700],
                                              ofItemAtPath: url.deletingLastPathComponent().path)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    func itemProvider() -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = name
        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier,
                                             visibility: .all) { completion in
            completion(png, nil); return nil
        }
        if let tiff {
            provider.registerDataRepresentation(forTypeIdentifier: UTType.tiff.identifier,
                                                 visibility: .all) { completion in
                completion(tiff, nil); return nil
            }
        }
        provider.registerFileRepresentation(forTypeIdentifier: UTType.png.identifier,
                                             fileOptions: [], visibility: .all) { completion in
            completion(file(), false, nil); return nil
        }
        return provider
    }

    func pasteboardItem() -> NSPasteboardItem? {
        guard let url = file() else { return nil }
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        if let tiff { item.setData(tiff, forType: .tiff) }
        item.setString(url.absoluteString, forType: .fileURL)
        return item
    }
}

/// AppKit supplies the end/cancel callback missing from SwiftUI's onDrag API.
struct ScreenshotPreviewDragSurface: NSViewRepresentable {
    let image: CGImage
    let transfer: () -> ScreenshotDragTransfer?
    let edit: () -> Void
    let dragging: (Bool) -> Void
    var swipe: ((Bool) -> Void)? = nil
    var dismiss: (() -> Void)? = nil

    func makeNSView(context: Context) -> Surface { Surface() }
    func updateNSView(_ view: Surface, context: Context) {
        view.image = image
        view.transfer = transfer
        view.edit = edit
        view.dragging = dragging
        view.swipe = swipe
        view.dismiss = dismiss
    }

    final class Surface: NSView, NSDraggingSource {
        var image: CGImage?
        var transfer: (() -> ScreenshotDragTransfer?)?
        var edit: (() -> Void)?
        var dragging: ((Bool) -> Void)?
        var swipe: ((Bool) -> Void)?
        var dismiss: (() -> Void)?
        private var down: NSEvent?
        private var started = false
        private var swiping = false
        private var trackpadTracking = false
        private var cancelled = false
        private var escapeMonitor: Any?
        private var sourceScreen: CGRect = .zero
        private var otherScreens: [CGRect] = []
        private var startPoint: CGPoint = .zero
        private var lastPoint: CGPoint = .zero
        private var swipeOrigin: CGPoint = .zero

        deinit { if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) } }

        override func mouseDown(with event: NSEvent) {
            guard !trackpadTracking else { return }
            down = event
            started = false
            swiping = false
            cancelled = false
            startPoint = window?.convertPoint(toScreen: event.locationInWindow) ?? .zero
            lastPoint = startPoint
            sourceScreen = window?.screen?.frame ?? .zero
            otherScreens = NSScreen.screens.filter { $0.frame != sourceScreen }.map(\.frame)
        }
        override func mouseUp(with event: NSEvent) {
            guard !trackpadTracking, down != nil else { return }
            lastPoint = window?.convertPoint(toScreen: event.locationInWindow) ?? lastPoint
            if swiping { finishSwipe(cancelled: cancelled) }
            else if !started { edit?() }
            down = nil
        }
        override func cancelOperation(_ sender: Any?) {
            cancelled = true
            if trackpadTracking { cancelTrackpadSwipe(); return }
            if swiping { finishSwipe(cancelled: true); return }
            super.cancelOperation(sender)
        }
        private func cancelTrackpadSwipe() {
            trackpadTracking = false
            swiping = false
            if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
            escapeMonitor = nil
            window?.setFrameOrigin(swipeOrigin)
            window?.alphaValue = 1
            swipe?(false)
        }
        override func scrollWheel(with event: NSEvent) {
            guard !swiping, !started, let window, let screen = window.screen,
                  ScreenshotPreviewSwipeGesture.canTrack(
                    deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY,
                    inverted: event.isDirectionInvertedFromDevice,
                    precise: event.hasPreciseScrollingDeltas,
                    enabled: NSEvent.isSwipeTrackingFromScrollEventsEnabled) else {
                super.scrollWheel(with: event)
                return
            }
            trackSwipe(event, in: window, screen: screen.frame)
        }

        private func trackSwipe(_ event: NSEvent, in window: NSWindow, screen: CGRect) {
            let inverted = event.isDirectionInvertedFromDevice
            let origin = window.frame.origin
            let travel = window.frame.maxX - screen.minX + 12
            swiping = true
            trackpadTracking = true
            swipeOrigin = origin
            swipe?(true)
            monitorEscape(forSwipe: true)
            event.trackSwipeEvent(options: [.lockDirection, .clampGestureAmount],
                dampenAmountThresholdMin: inverted ? 0 : -1,
                max: inverted ? 1 : 0) { [weak self, weak window] amount, phase, complete, stop in
                guard let self, let window else { return }
                guard self.trackpadTracking else { stop.pointee = true; return }
                let progress = ScreenshotPreviewSwipeGesture.trackpadProgress(
                    amount: amount, inverted: inverted)
                if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || phase != [] || complete {
                    self.moveSwipe(window, offset: -progress * travel, origin: origin)
                    window.alphaValue = 1 - progress
                }
                guard complete else { return }
                self.trackpadTracking = false
                self.swiping = false
                if let escapeMonitor = self.escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
                self.escapeMonitor = nil
                if progress >= 0.95 { self.dismiss?() }
                else { window.setFrameOrigin(origin); window.alphaValue = 1; self.swipe?(false) }
            }
        }

        override func mouseDragged(with event: NSEvent) {
            guard !trackpadTracking else { return }
            let point = window?.convertPoint(toScreen: event.locationInWindow) ?? .zero
            lastPoint = point
            if swiping { updateSwipe(to: point); return }
            guard !started, let down else { return }
            let dx = point.x - startPoint.x
            let dy = point.y - startPoint.y
            guard hypot(dx, dy) > 7 else { return }
            if ScreenshotPreviewSwipeGesture.canBegin(dx: dx, dy: dy,
                sourceScreen: sourceScreen, otherScreens: otherScreens,
                y: point.y), let window {
                started = true
                swiping = true
                swipeOrigin = window.frame.origin
                swipe?(true)
                monitorEscape(forSwipe: true)
                updateSwipe(to: point)
                return
            }
            guard let image, let writer = transfer?()?.pasteboardItem() else { return }
            started = true
            dragging?(true)
            let item = NSDraggingItem(pasteboardWriter: writer)
            item.setDraggingFrame(bounds, contents: NSImage(cgImage: image, size: bounds.size))
            monitorEscape(forSwipe: false)
            let session = beginDraggingSession(with: [item], event: down, source: self)
            session.animatesToStartingPositionsOnCancelOrFail = true
        }
        private func updateSwipe(to point: CGPoint) {
            guard let window else { return }
            moveSwipe(window, offset: point.x - startPoint.x, origin: swipeOrigin)
        }

        private func moveSwipe(_ window: NSWindow, offset: CGFloat, origin: CGPoint) {
            let dx = min(0, offset)
            window.setFrameOrigin(CGPoint(x: origin.x + dx, y: origin.y))
            window.alphaValue = max(0.65, 1 + dx / max(window.frame.width, 1) * 0.35)
        }

        private func finishSwipe(cancelled: Bool) {
            guard swiping, let window else { return }
            swiping = false
            down = nil
            if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
            escapeMonitor = nil
            let dx = lastPoint.x - startPoint.x
            let dy = lastPoint.y - startPoint.y
            let dismisses = ScreenshotPreviewSwipeGesture.shouldDismiss(
                dx: dx, dy: dy, width: window.frame.width,
                startX: startPoint.x, screenMinX: sourceScreen.minX,
                cancelled: cancelled)
            let targetX = dismisses
                ? ScreenshotPreviewSwipeGesture.exitX(screenMinX: sourceScreen.minX,
                                                       width: window.frame.width)
                : swipeOrigin.x
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                    ? 0 : (dismisses ? 0.18 : 0.22)
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrameOrigin(CGPoint(x: targetX, y: swipeOrigin.y))
                window.animator().alphaValue = dismisses ? 0 : 1
            }, completionHandler: { [weak self] in
                if dismisses { self?.dismiss?() }
                else { self?.started = false; self?.swipe?(false) }
            })
        }

        private func monitorEscape(forSwipe: Bool) {
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53 else { return event }
                self?.cancelled = true
                if forSwipe {
                    if self?.trackpadTracking == true { self?.cancelTrackpadSwipe() }
                    else { self?.finishSwipe(cancelled: true) }
                    return nil
                }
                return event
            }
        }
        func draggingSession(_ session: NSDraggingSession,
                             sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
        func draggingSession(_ session: NSDraggingSession, endedAt point: NSPoint,
                             operation: NSDragOperation) {
            down = nil
            started = false
            if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
            escapeMonitor = nil
            dragging?(false)
        }
    }
}

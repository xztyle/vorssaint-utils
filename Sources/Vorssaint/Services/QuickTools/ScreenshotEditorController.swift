// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import SwiftUI

// MARK: - Window controller

/// Hosts one editor window per capture and owns everything with a side
/// effect: clipboard, files, pins, text recognition and the close-confirm.
final class ScreenshotEditorController: NSObject, NSWindowDelegate {
    let model: ScreenshotEditorModel
    let preferences: UserDefaults
    let fixtureDirectory: URL?
    var onCommit: ((ScreenshotRenderer.Export) -> Void)?
    var onClose: (() -> Void)?
    var returnsToPreview: Bool { onCommit != nil }
    var allowsExternalActions: Bool { fixtureDirectory == nil }
    private var window: NSWindow?
    private var keyMonitor: Any?
    private var scrollMonitor: Any?

    var protectedWindowIDs: Set<CGWindowID> {
        guard let window, window.isVisible, window.windowNumber > 0 else { return [] }
        return [CGWindowID(window.windowNumber)]
    }
    private var strings: ScreenshotFeatureStrings {
        FeatureStrings.screenshot(L10n.shared.language)
    }

    init(capture: ScreenshotSelectionController.Capture, preferences: UserDefaults = .standard,
         fixtureDirectory: URL? = nil, flattened: Bool = false) {
        self.preferences = preferences
        self.fixtureDirectory = fixtureDirectory
        model = ScreenshotEditorModel(image: capture.image, scale: capture.scale,
                                      preferences: preferences, flattened: flattened)
        super.init()
    }

    func show() {
        let screen = NSScreen.pointerVisibleFrame
        let minimumSize = ScreenshotSupport.editorMinimumContentSize(visibleSize: screen.size)
        // The hosting view rewrites the window's size limits on its first
        // layout pass, so a contentMinSize set on the window is silently
        // lost. Declare the minimum on the hosted view and track just that:
        // the hosting controller then maintains contentMinSize itself.
        let content = ScreenshotEditorView(model: model, controller: self)
            .defaultAppStorage(preferences)
            .frame(minWidth: minimumSize.width, minHeight: minimumSize.height)
        let host = NSHostingController(rootView: content)
        host.sizingOptions = [.minSize]
        let window = NSWindow(contentViewController: host)
        // One continuous surface: the canvas fills the window and the
        // controls float over it, so the editor reads as a single object.
        window.title = strings.editorTitle
        if fixtureDirectory != nil { window.level = .statusBar }
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // Keep the editor dark so canvas contrast and popovers stay consistent.
        window.appearance = NSAppearance(named: .darkAqua)
        // Content drags edit annotations. Only the title strip moves the window.
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]

        // Chrome must equal the view's designed margins exactly (rail 64 +
        // sides, action band above, style band below), so a fresh window
        // opens with zero leftover stage around the capture.
        let contentSize = ScreenshotSupport.editorContentSize(
            imagePointSize: model.pointSize,
            visibleSize: screen.size)
        window.setContentSize(contentSize)
        window.center()

        self.window = window
        installKeyMonitor()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // Let the window appear before starting competing Vision workloads.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window?.isVisible == true else { return }
            self.model.recognizeText()
            self.model.recognizeQRCodes()
        }
    }

    func bringForward() { window?.makeKeyAndOrderFront(nil) }

    func close() {
        window?.close()
    }

    /// Closes without the discard confirmation used by the titlebar button.
    func discardAndClose() {
        window?.close()
    }

    // MARK: Keyboard

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window,
                  ScreenshotSupport.editorOwnsKeyEvent(
                    eventWindowNumber: event.windowNumber,
                    editorWindowNumber: window.windowNumber,
                    editorIsKey: window.isKeyWindow)
            else { return event }
            // The recorder owns every key, including editor commands.
            if ShortcutCapture.isCapturing { return event }
            // While a text field edits, every key belongs to it.
            if window.firstResponder is NSText || self.model.editingTextID != nil {
                return event
            }
            return self.handleKey(event) ? nil : event
        }
        // Control-scroll adjusts canvas zoom.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, let window = self.window,
                  ScreenshotSupport.editorOwnsKeyEvent(
                    eventWindowNumber: event.windowNumber,
                    editorWindowNumber: window.windowNumber,
                    editorIsKey: window.isKeyWindow),
                  event.modifierFlags.contains(.control)
            else { return event }
            let delta = event.scrollingDeltaY
            guard delta != 0 else { return nil }
            let clamped = max(-24, min(24, delta))
            self.model.adjustZoom(by: 1 + clamped * 0.014)
            return nil
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = Int(event.keyCode)

        let orderRaw = preferences.string(forKey: DefaultsKey.screenshotToolOrder)
        let bindingsRaw = preferences.string(forKey: DefaultsKey.screenshotToolShortcuts)
        let enabled = preferences.bool(forKey: DefaultsKey.screenshotToolShortcutsEnabled)
        let number = event.characters?.first.flatMap { Int(String($0)) }
        if let tool = ScreenshotSupport.Tool.shortcutTool(
            keyCode: Int64(key), modifiers: GlobalShortcutModifiers(eventFlags: flags),
            number: number, orderRaw: orderRaw, bindingsRaw: bindingsRaw, enabled: enabled,
            capsLockOn: flags.contains(.capsLock)) {
            model.tool = tool
            return true
        }

        if flags.contains(.command) {
            switch key {
            case kVK_ANSI_C:
                // Text selected on the canvas copies as text and keeps the
                // editor open; otherwise the capture leaves as an image.
                if !model.selectedWordIndexes.isEmpty {
                    copySelectedText()
                } else {
                    copyToClipboard()
                }
                return true
            case kVK_ANSI_S:
                if flags.contains(.shift) { saveAs() } else { save() }
                return true
            case kVK_ANSI_Z:
                if flags.contains(.shift) { model.redo() } else { model.undo() }
                return true
            case kVK_ANSI_P: pin(); return true
            case kVK_Delete, kVK_ForwardDelete:
                discardAndClose()
                return true
            case kVK_ANSI_0: model.zoomOverride = nil; return true
            case kVK_ANSI_1: model.zoomOverride = 1 / model.scale; return true
            case kVK_ANSI_Equal: model.adjustZoom(by: 1.25); return true
            case kVK_ANSI_Minus: model.adjustZoom(by: 0.8); return true
            default:
                return false
            }
        }
        guard flags.isDisjoint(with: [.command, .control, .option]) else { return false }

        switch key {
        case kVK_Delete, kVK_ForwardDelete:
            model.deleteSelected()
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if model.tool == .crop, model.cropDraft != nil {
                model.applyCrop()
            } else if returnsToPreview {
                applyAndClose()
            } else {
                copyToClipboard()
            }
            return true
        case kVK_Escape:
            if model.tool == .crop, model.cropDraft != nil {
                model.tool = .select
            } else if !model.selectedWordIndexes.isEmpty {
                model.clearTextSelection()
            } else if model.selectedID != nil {
                model.selectedID = nil
            } else {
                window?.performClose(nil)
            }
            return true
        default:
            return false
        }
    }

    /// Done commits pixels without writing to the general clipboard or save folder.
    func applyAndClose() {
        if model.cropDraft != nil { model.applyCrop() }
        guard let export = model.exportImage() else { NSSound.beep(); return }
        commit(export)
        window?.close()
    }

    func commit(_ export: ScreenshotRenderer.Export) {
        onCommit?(export)
        model.markExported()
    }

    // MARK: Export actions

    /// Uploads the rendered editor result without copying the URL or closing
    /// the editor. The view presents the owner controls after it succeeds.
    func share(duration: ScreenshotShareDuration,
               completion: @escaping (ScreenshotShareRecord?) -> Void) {
        guard allowsExternalActions, let export = model.exportImage() else {
            QuickToolHUD.show(icon: "link", message: strings.shareFailedHUD)
            completion(nil)
            return
        }
        Task { @MainActor [weak self] in
            guard let self else {
                completion(nil)
                return
            }
            let data = await Task.detached(priority: .userInitiated) {
                ScreenshotRenderer.pngData(from: export.image, scale: export.scale)
            }.value
            guard let data else {
                QuickToolHUD.show(icon: "link", message: self.strings.shareFailedHUD)
                completion(nil)
                return
            }
            do {
                let record = try await ScreenshotShareService.shared.createLink(
                    pngData: data, duration: duration)
                guard self.window != nil else {
                    try? await ScreenshotShareService.shared.delete(record)
                    completion(nil)
                    return
                }
                self.model.markExported()
                completion(record)
            } catch {
                QuickToolHUD.show(icon: "link", message: self.strings.shareFailedHUD)
                NSSound.beep()
                completion(nil)
            }
        }
    }

    func dragItemProvider(_ export: ScreenshotRenderer.Export) -> NSItemProvider? {
        ScreenshotDragTransfer(image: export.image, scale: export.scale,
                               prefix: strings.fileNamePrefix, directory: fixtureDirectory)?.itemProvider()
    }

    /// The edited image as it would be saved, in a temporary file for the
    /// system share sheet.
    func shareFile() -> URL? {
        guard allowsExternalActions else { return nil }
        guard let export = model.exportImage() else { return nil }
        return ScreenshotService.temporaryExportFile(image: export.image, scale: export.scale,
                                                     strings: strings)
    }

    /// Every final output closes the editor: the capture leaves the app
    /// and the window's job is done, so nothing lingers to tidy up.
    func copyToClipboard() {
        guard allowsExternalActions else { return }
        guard let export = model.exportImage() else { return }
        guard Self.copyImage(export, fileNamePrefix: strings.fileNamePrefix) else {
            NSSound.beep()
            return
        }
        commit(export)
        QuickToolHUD.show(icon: "camera.viewfinder", message: strings.copiedHUD)
        window?.close()
    }

    @discardableResult
    static func copyImage(_ export: ScreenshotRenderer.Export, fileNamePrefix: String) -> Bool {
        guard let data = ScreenshotRenderer.pngData(from: export.image, scale: export.scale),
              let base = FileManager.default.urls(for: .cachesDirectory,
                                                  in: .userDomainMask).first,
              let bundleID = Bundle.main.bundleIdentifier
        else { return false }
        let folder = base.appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Copied Screenshots", isDirectory: true)
        let name = ScreenshotSupport.fileName(prefix: fileNamePrefix, date: Date())
        guard let url = try? ScreenshotSupport.copiedFile(data: data, name: name,
                                                         directory: folder) else {
            return false
        }
        guard copyFile(url, payload: clipboardPayload(from: export, png: data)) else {
            try? FileManager.default.removeItem(at: url)
            return false
        }
        ScreenshotSupport.pruneCopiedFiles(in: folder, preserving: url)
        return true
    }

    @discardableResult
    static func copyFile(_ url: URL, payload: ClipboardPayload? = nil) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        guard item.setString(url.absoluteString, forType: .fileURL) else { return false }
        if let png = payload?.png {
            item.setData(png, forType: .png)
        }
        if let tiff = payload?.tiff {
            item.setData(tiff, forType: .tiff)
        }
        return pasteboard.writeObjects([item])
    }

    struct ClipboardPayload: Sendable {
        let png: Data?
        let tiff: Data?
    }

    static func clipboardPayload(from export: ScreenshotRenderer.Export) -> ClipboardPayload {
        clipboardPayload(from: export,
                         png: ScreenshotRenderer.pngData(from: export.image, scale: export.scale))
    }

    static func clipboardPayload(from export: ScreenshotRenderer.Export,
                                 png: Data?) -> ClipboardPayload {
        ClipboardPayload(png: png,
                         tiff: ScreenshotRenderer.tiffData(from: export.image, scale: export.scale))
    }

    @discardableResult
    static func copyClipboardPayload(_ payload: ClipboardPayload) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        if let png = payload.png {
            item.setData(png, forType: .png)
        }
        if let tiff = payload.tiff {
            item.setData(tiff, forType: .tiff)
        }
        return pasteboard.writeObjects([item])
    }

    func save() {
        guard allowsExternalActions else { applyAndClose(); return }
        guard let export = model.exportImage(),
              let data = ScreenshotRenderer.pngData(from: export.image, scale: export.scale)
        else { return }
        let (url, consumedNumber) = ScreenshotService.saveDestination(strings: strings)
        do {
            try data.write(to: url, options: .atomic)
            ScreenshotSupport.markAsScreenCapture(url)
            commit(export)
            QuickToolHUD.show(icon: "camera.viewfinder",
                              message: String(format: strings.savedHUDFormat,
                                              url.deletingLastPathComponent().lastPathComponent))
            window?.close()
        } catch {
            if let consumedNumber {
                ScreenshotService.rewindNumberSequence(toReuse: consumedNumber)
            }
            NSSound.beep()
        }
    }

    func saveAs() {
        guard allowsExternalActions else { applyAndClose(); return }
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = ScreenshotSupport.fileName(
            prefix: strings.fileNamePrefix, date: Date())
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            guard let export = self.model.exportImage(),
                  let data = ScreenshotRenderer.pngData(from: export.image, scale: export.scale)
            else { return }
            do {
                try data.write(to: url, options: .atomic)
                self.commit(export)
                self.window?.close()
            } catch {
                NSSound.beep()
            }
        }
    }

    /// Pinning snapshots the current export and leaves the editor open.
    func pin() {
        guard allowsExternalActions else { return }
        guard let export = model.exportImage(withBackdrop: false) else { return }
        ScreenshotPinController.shared.pin(image: export.image, scale: export.scale)
        model.markExported()
    }

    /// Copies the words selected on the canvas as plain text.
    func copySelectedText() {
        guard allowsExternalActions else { return }
        let text = model.selectedText
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        QuickToolHUD.show(icon: "text.viewfinder", message: L10n.shared.s.ocrCopied)
    }

    /// Shows the detected code's content in the shared result panel; the
    /// editor stays open behind it so the capture can still be worked on.
    func showQRResult() {
        guard let reading = model.qrReading else { return }
        QRResultController.shared.show(reading: reading)
    }

    // MARK: NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model.isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = strings.discardTitle
        alert.informativeText = strings.discardMessage
        alert.addButton(withTitle: strings.discardConfirm)
        alert.addButton(withTitle: strings.cancel)
        alert.alertStyle = .warning
        return alert.runModal() == .alertFirstButtonReturn
    }

    func windowWillClose(_ notification: Notification) {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        window?.delegate = nil
        window = nil
        if let onClose { onClose() }
        else { ScreenshotService.shared.editorDidClose(self) }
    }
}

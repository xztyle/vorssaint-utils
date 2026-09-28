// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CryptoKit
import ImageIO

/// Exists only in explicit capture-fixture mode. The text view uses AppKit's
/// image import and reads only the drag pasteboard, never the general clipboard.
final class ScreenshotFixtureReceiver: NSObject {
    private let workspace: ScreenshotCaptureWorkspace
    private let directory: URL
    private var window: NSWindow?
    private weak var receiverView: NSView?
    private var geometryObservers: [NSObjectProtocol] = []
    private let status = NSTextField(labelWithString: "Drop an edited corner image into the text input below.")

    init(workspace: ScreenshotCaptureWorkspace, directory: URL) {
        self.workspace = workspace
        self.directory = directory
    }

    deinit { geometryObservers.forEach(NotificationCenter.default.removeObserver) }

    func show() {
        guard window == nil else { window?.makeKeyAndOrderFront(nil); return }
        let panel = NSWindow(contentRect: .init(x: 0, y: 0, width: 640, height: 650),
                             styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = "Aster Capture Fixture — Controls and Drop Receiver"
        panel.level = .statusBar
        panel.isReleasedWhenClosed = false
        panel.contentView = content()
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        let screen = NSScreen.main?.visibleFrame ?? .init(x: 0, y: 0, width: 1440, height: 900)
        panel.setFrameOrigin(.init(x: min(screen.minX + 390, screen.maxX - 650), y: screen.minY + 16))
        window = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        observeGeometry()
        recordGeometry()
    }

    private func content() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = .init(top: 16, left: 16, bottom: 16, right: 16)
        for (index, item) in workspace.items.enumerated() { stack.addArrangedSubview(controls(index, id: item.id)) }
        status.lineBreakMode = .byWordWrapping
        status.maximumNumberOfLines = 3
        stack.addArrangedSubview(status)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let receiver = DropTextView(frame: .init(x: 0, y: 0, width: 590, height: 430), textContainer: nil)
        receiver.directory = directory
        receiver.completed = { [weak self] in self?.status.stringValue = $0 }
        scroll.documentView = receiver
        receiverView = scroll.contentView
        stack.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 430).isActive = true
        return stack
    }

    private func controls(_ index: Int, id: UUID) -> NSView {
        let label = NSTextField(labelWithString: "Capture \(index + 1) · \(id.uuidString.prefix(8))")
        let preview = NSButton(title: "Preview \(index + 1)", target: self, action: #selector(showPreview(_:)))
        let edit = NSButton(title: "Edit \(index + 1)", target: self, action: #selector(editCapture(_:)))
        preview.identifier = NSUserInterfaceItemIdentifier(id.uuidString)
        edit.identifier = preview.identifier
        let row = NSStackView(views: [label, preview, edit])
        row.spacing = 10
        return row
    }

    @objc private func showPreview(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let id = UUID(uuidString: raw),
              let item = workspace.items.first(where: { $0.id == id }) else { return }
        item.preview?.bringForward(takingFocus: true)
        recordGeometry()
    }

    @objc private func editCapture(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let id = UUID(uuidString: raw) else { return }
        workspace.openEditor(id: id)
        recordGeometry()
    }

    private func observeGeometry() {
        guard geometryObservers.isEmpty else { return }
        let names: [Notification.Name] = [NSWindow.didMoveNotification, NSWindow.didResizeNotification,
                                          NSWindow.didBecomeKeyNotification, NSWindow.didChangeOcclusionStateNotification]
        geometryObservers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.recordGeometry()
            }
        }
    }

    private func recordGeometry() {
        var receipt: [String: Any] = ["coordinateSystem": "AppKit screen points, origin bottom left",
                                    "windows": NSApp.windows.filter(\.isVisible).map(Self.geometry)]
        if let window, let receiverView {
            let rect = receiverView.convert(receiverView.bounds, to: nil)
            receipt["receiverInput"] = Self.rectangle(window.convertToScreen(rect))
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
            try RecentCaptureStore.write(data, to: directory.appendingPathComponent("ui-geometry.json"))
        } catch { fputs("Capture fixture geometry failed: \(error)\n", stderr) }
    }

    private static func geometry(_ window: NSWindow) -> [String: Any] {
        ["title": window.title, "windowNumber": window.windowNumber, "key": window.isKeyWindow,
         "frame": rectangle(window.frame), "content": rectangle(window.contentRect(forFrameRect: window.frame))]
    }

    private static func rectangle(_ rect: CGRect) -> [String: CGFloat] {
        ["x": rect.minX, "y": rect.minY, "width": rect.width, "height": rect.height]
    }

    private final class DropTextView: NSTextView {
        var directory: URL?
        var completed: ((String) -> Void)?
        private(set) var importedType: NSPasteboard.PasteboardType?
        private let ownedTextStorage: NSTextStorage?

        override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
            let owned = container == nil ? Self.textSystem(width: frameRect.width) : nil
            ownedTextStorage = owned?.storage
            super.init(frame: frameRect, textContainer: container ?? owned?.container)
            configure()
        }

        private static func textSystem(width: CGFloat) -> (storage: NSTextStorage, container: NSTextContainer) {
            let storage = NSTextStorage()
            let layout = NSLayoutManager()
            let container = NSTextContainer(size: .init(width: width, height: CGFloat.greatestFiniteMagnitude))
            storage.addLayoutManager(layout)
            layout.addTextContainer(container)
            return (storage, container)
        }

        private func configure() {
            isRichText = true
            importsGraphics = true
            isEditable = true
            isVerticallyResizable = true
            isHorizontallyResizable = false
            textContainer?.widthTracksTextView = true
            autoresizingMask = [.width]
            textContainerInset = .init(width: 12, height: 12)
            font = .systemFont(ofSize: 17)
            string = "Image-capable text input\n"
            setAccessibilityLabel("Capture fixture image input")
            registerForDraggedTypes([.png])
        }

        required init?(coder: NSCoder) { nil }
        override func copy(_ sender: Any?) {}
        override func cut(_ sender: Any?) {}
        override func paste(_ sender: Any?) {}
        override func pasteAsPlainText(_ sender: Any?) {}
        override func pasteAsRichText(_ sender: Any?) {}

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            sender.draggingPasteboard.types?.contains(.png) == true ? .copy : []
        }
        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
        override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            let board = sender.draggingPasteboard
            guard let directory, let png = board.data(forType: .png),
                  let source = CGImageSourceCreateWithData(png as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return false }
            setSelectedRange(NSRange(location: textStorage?.length ?? 0, length: 0))
            let accepted = importImage(from: board)
            return record(png, image: image, directory: directory, board: board, accepted: accepted)
        }

        func importImage(from board: NSPasteboard) -> Bool {
            let before = attachmentCount
            importedType = nil
            for type in [NSPasteboard.PasteboardType.png, .tiff] {
                guard board.types?.contains(type) == true else { continue }
                if readSelection(from: board, type: type), attachmentCount > before {
                    importedType = type
                    return true
                }
            }
            return false
        }

        private var attachmentCount: Int {
            var count = 0
            textStorage?.enumerateAttribute(.attachment, in: NSRange(location: 0, length: textStorage?.length ?? 0)) {
                value, _, _ in if value is NSTextAttachment { count += 1 }
            }
            return count
        }

        private func record(_ png: Data, image: CGImage, directory: URL,
                            board: NSPasteboard, accepted: Bool) -> Bool {
            let stem = "received-\(UUID().uuidString)"
            let receipt: [String: Any] = [
                "acceptedByRichTextInput": accepted, "attachmentCount": attachmentCount,
                "importedType": importedType?.rawValue ?? "",
                "file": stem + ".png", "width": image.width, "height": image.height,
                "sha256": SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined(),
                "dragTypes": board.types?.map(\.rawValue) ?? []]
            do {
                try RecentCaptureStore.write(png, to: directory.appendingPathComponent(stem + ".png"))
                let json = try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
                try RecentCaptureStore.write(json, to: directory.appendingPathComponent(stem + ".json"))
                completed?("\(accepted ? "Accepted" : "Rejected") · \(image.width) × \(image.height) · \(stem).png")
                return accepted
            } catch { completed?("Receiver could not save evidence: \(error)"); return false }
        }
    }
}

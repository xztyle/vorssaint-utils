// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// A SwiftUI onDrag supplies one pasteboard item. File clips can contain many
/// URLs, so their icon starts one native dragging item for each saved file.
struct ClipboardFileDragSource: NSViewRepresentable {
    let paths: [String]
    let onSelect: () -> Void
    let onActivate: () -> Void

    func makeNSView(context: Context) -> DragView { DragView() }

    func updateNSView(_ view: DragView, context: Context) { view.source = self }

    final class DragView: NSView, NSDraggingSource {
        var source: ClipboardFileDragSource?
        private var start: NSPoint?

        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) { start = event.locationInWindow }

        override func mouseUp(with event: NSEvent) {
            guard start != nil else { return }
            start = nil
            if event.clickCount >= 2 { source?.onActivate() }
            else { source?.onSelect() }
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start, let source,
                  hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) >= 4 else { return }
            self.start = nil
            guard let urls = ClipboardFileDragPayload.urls(paths: source.paths) else { NSSound.beep(); return }
            let items = urls.map { url in
                let item = NSDraggingItem(pasteboardWriter: url as NSURL)
                item.setDraggingFrame(bounds, contents: NSWorkspace.shared.icon(forFile: url.path))
                return item
            }
            beginDraggingSession(with: items, event: event, source: self)
        }

        func draggingSession(_ session: NSDraggingSession,
                             sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    }
}

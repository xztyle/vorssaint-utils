// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import AppKit
import SwiftUI

enum ClipboardPopoverTests {
    class EditorState {
        var quickPreviewWindow: NSWindow?
        var cancelEditRequest = UUID()
    }

    final class Editor: NSTextView {
        var composing = false
        override func hasMarkedText() -> Bool { composing }
    }

    static func run(_ suite: TestSuite) {
        windowScope(suite)
        escapeSequence(suite)
        nativeEditorCancel(suite)
    }

    private static func windowScope(_ suite: TestSuite) {
        _ = NSApplication.shared
        let windows = (0..<3).map { _ in makeWindow() }
        windows.forEach { $0.isReleasedWhenClosed = false }
        defer { windows.forEach { $0.close() } }
        let scope = ClipboardLibraryWindowScope(drawer: windows[0], preview: windows[1])
        suite.expect(scope.owns(windows[0]) && scope.owns(windows[1]),
                     "drawer and native preview receive the same library keys")
        suite.expect(!scope.owns(windows[2]) && !scope.owns(nil),
                     "other Aster windows and missing event windows remain outside")
        suite.expect(scope.owns(windowNumber: windows[0].windowNumber)
                     && scope.owns(windowNumber: windows[1].windowNumber),
                     "global click routing recognizes both exact library windows")
        suite.expect(!scope.owns(windowNumber: windows[2].windowNumber)
                     && !scope.owns(windowNumber: 0) && !scope.owns(windowNumber: -1),
                     "unknown and foreign window numbers cannot keep the drawer open")
        let closed = ClipboardLibraryWindowScope(drawer: windows[0], preview: nil)
        suite.expect(!closed.owns(windows[1]) && !closed.owns(windowNumber: windows[1].windowNumber),
                     "a closed preview no longer suppresses outside dismissal")
        suite.expect(!scope.contains(NSPoint(x: -9950, y: -9950)),
                     "hidden library windows cannot suppress clicks by their old bounds")
        editorEscape(suite, preview: windows[1], other: windows[2])
    }

    private static func makeWindow() -> NSWindow {
        NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 100, height: 100),
                 styleMask: [.borderless], backing: .buffered, defer: false)
    }

    private static func nativeEditorCancel(_ suite: TestSuite) {
        var cancellations = 0
        let coordinator = PlainTextEditor.Coordinator(text: .constant("draft"), selectedRange: nil,
                                                     onCancel: { cancellations += 1 })
        let editor = Editor()
        let cancel = #selector(NSResponder.cancelOperation(_:))
        suite.expect(coordinator.textView(editor, doCommandBy: cancel) && cancellations == 1,
                     "native text editing cancels its draft even when the window monitor does not receive Escape")
        editor.composing = true
        suite.expect(!coordinator.textView(editor, doCommandBy: cancel) && cancellations == 1,
                     "native Escape first cancels marked input rather than the draft")
        editor.composing = false
        suite.expect(!coordinator.textView(editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))
                     && cancellations == 1, "ordinary text commands stay with the editor")
        coordinator.onCancel = nil
        suite.expect(!coordinator.textView(editor, doCommandBy: cancel),
                     "existing scratchpad editors keep native cancellation when no draft callback is supplied")
    }

    private static func editorEscape(_ suite: TestSuite, preview: NSWindow, other: NSWindow) {
        let service = EditorService()
        service.quickPreviewWindow = preview
        let editor = Editor()
        preview.contentView = editor
        preview.makeFirstResponder(editor)
        let escape = key(53, window: preview)
        let initial = service.cancelEditRequest
        editor.isEditable = false
        suite.expect(!service.cancelPreviewEditor(with: escape) && service.cancelEditRequest == initial,
                     "Escape in a read-only preview continues to close its popover")
        editor.isEditable = true
        suite.expect(service.cancelPreviewEditor(with: escape) && service.cancelEditRequest != initial,
                     "the actual key handler cancels a draft before closing the preview")
        let cancelled = service.cancelEditRequest
        suite.expect(!service.cancelPreviewEditor(with: key(36, window: preview))
                     && !service.cancelPreviewEditor(with: key(53, window: other))
                     && !service.cancelPreviewEditor(with: key(53, window: preview, modifiers: .option))
                     && service.cancelEditRequest == cancelled,
                     "ordinary, foreign-window and modified keys leave the draft intact")
        editor.isFieldEditor = true
        suite.expect(!service.cancelPreviewEditor(with: escape), "search field Escape retains search routing")
        editor.isFieldEditor = false
        editor.composing = true
        suite.expect(!service.cancelPreviewEditor(with: escape), "input-method Escape belongs to composition")
    }

    private static func key(_ code: UInt16, window: NSWindow,
                            modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
    }

    private static func escapeSequence(_ suite: TestSuite) {
        for batch in [0, 2] {
            for empty in [true, false] {
                suite.expect(ClipboardHistoryEscape.action(batchCount: batch,
                    previewIsPresented: true, queryIsEmpty: empty) == .closePreview,
                    "Escape closes the native preview before changing search or a batch")
            }
        }
        suite.expect(ClipboardHistoryEscape.action(batchCount: 2, queryIsEmpty: false) == .clearBatchSelection,
                     "the next Escape clears a batch without discarding the query")
        suite.expect(ClipboardHistoryEscape.action(batchCount: 0, queryIsEmpty: false) == .clearQuery,
                     "Escape then clears search while preserving the drawer")
        suite.expect(ClipboardHistoryEscape.action(batchCount: 0) == .hideWindow,
                     "only the final Escape dismisses the drawer")
        suite.expect(ClipboardHistoryFocus.textViewOwnsKeys(isComposing: false,
            isFieldEditor: false, isEditable: false, copyingSelection: true),
            "copying a selected preview fragment does not copy the entire card")
        suite.expect(!ClipboardHistoryFocus.textViewOwnsKeys(isComposing: false,
            isFieldEditor: false, isEditable: false),
            "the read-only preview retains library navigation and Escape")
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import AppKit
import SwiftUI

/// A native popover keeps the timeline fixed and places the preview above its
/// card. Its exact window is included in the drawer's keyboard/click scope.
struct ClipboardEntryPreviewPopover: NSViewRepresentable {
    let entry: ClipboardHistoryEntry
    let isPresented: Bool
    @Binding var isEditing: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ClipboardPreviewAnchorView {
        let view = ClipboardPreviewAnchorView()
        view.attached = { [weak coordinator = context.coordinator] in coordinator?.synchronize() }
        context.coordinator.anchor = view
        return view
    }

    func updateNSView(_ view: ClipboardPreviewAnchorView, context: Context) {
        context.coordinator.configure(entry: entry, presented: isPresented, editing: $isEditing)
    }

    static func dismantleNSView(_ view: ClipboardPreviewAnchorView, coordinator: Coordinator) {
        view.attached = nil
        coordinator.close()
    }

    final class Coordinator: NSObject, NSPopoverDelegate {
        weak var anchor: NSView?
        private let popover = NSPopover()
        private var entryID: UUID?
        private var wantsPresentation = false
        private var pending: DispatchWorkItem?
        private weak var previewWindow: NSWindow?
        private var history: ClipboardHistoryService { .shared }

        override init() {
            super.init()
            popover.behavior = .applicationDefined
            popover.delegate = self
        }

        func configure(entry: ClipboardHistoryEntry, presented: Bool, editing: Binding<Bool>) {
            entryID = entry.id
            wantsPresentation = presented
            guard presented else { close(); return }
            let content = ClipboardEntryPreview(
                text: FeatureStrings.clipboard(L10n.shared.language), entry: entry,
                isEditing: editing, onClose: { ClipboardHistoryService.shared.setQuickPreviewPresented(false) })
                .frame(width: 420, height: 360)
                .background(Color(nsColor: .windowBackgroundColor))
            if let host = popover.contentViewController as? NSHostingController<AnyView> {
                host.rootView = AnyView(content)
            } else {
                popover.contentViewController = NSHostingController(rootView: AnyView(content))
            }
            scheduleSynchronization()
        }

        private func scheduleSynchronization() {
            pending?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.synchronize() }
            pending = work
            DispatchQueue.main.async(execute: work)
        }

        func synchronize() {
            guard wantsPresentation, history.quickPreviewPresented,
                  entryID == history.selectedQuickEntryID,
                  let anchor, anchor.window?.isVisible == true,
                  anchor.bounds.width > 0, anchor.bounds.height > 0 else { return }
            guard !popover.isShown else { return }
            popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
            registerWindow()
        }

        func popoverDidShow(_ notification: Notification) { registerWindow() }

        private func registerWindow() {
            previewWindow = popover.contentViewController?.view.window
            history.quickPreviewWindow = previewWindow
            if let drawer = history.panel {
                previewWindow?.level = NSWindow.Level(rawValue: drawer.level.rawValue + 1)
                previewWindow?.collectionBehavior = drawer.collectionBehavior
            }
        }

        func close() {
            wantsPresentation = false
            pending?.cancel()
            pending = nil
            if popover.isShown { popover.close() }
        }

        func popoverDidClose(_ notification: Notification) {
            if history.quickPreviewWindow === previewWindow { history.quickPreviewWindow = nil }
            previewWindow = nil
            if !wantsPresentation { popover.contentViewController = nil }
            guard entryID == history.selectedQuickEntryID else { return }
            if wantsPresentation && history.quickPreviewPresented {
                scheduleSynchronization()
                return
            }
            history.setQuickPreviewPresented(false)
            if history.drawerPresentation.isPresented { history.panel?.makeKey() }
        }
    }
}

final class ClipboardPreviewAnchorView: NSView {
    var attached: (() -> Void)?
    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attached?()
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Owns one committed snapshot per capture. Output closures always receive that
/// snapshot, including after an editor replaces it with its flattened export.
final class ScreenshotCaptureWorkspace {
    typealias Capture = ScreenshotSelectionController.Capture
    typealias Action = ScreenshotQuickPreviewController.Action
    final class Item {
        let id: UUID
        var capture: Capture
        var revision = 0
        var preview: ScreenshotQuickPreviewController?
        var editor: ScreenshotEditorController?
        init(id: UUID, capture: Capture) { self.id = id; self.capture = capture }
        var active: Bool { editor != nil || preview?.isInteracting == true }
    }

    private(set) var items: [Item] = []
    var output: (UUID, Capture, Action) -> Set<Action> = { _, _, _ in [] }
    var share: (Capture, ScreenshotShareDuration,
                @escaping (ScreenshotShareRecord?) -> Void) -> Void = { _, _, completion in completion(nil) }
    var shareFile: (Capture) -> URL? = { _ in nil }
    var committed: (UUID, Capture, Int) -> Void = { _, _, _ in }
    var dismissed: (UUID) -> Void = { _ in }
    let preferences: UserDefaults
    let fixtureDirectory: URL?
    private var displayObserver: NSObjectProtocol?
    private var stopping = false

    init(preferences: UserDefaults = .standard, fixtureDirectory: URL? = nil) {
        self.preferences = preferences
        self.fixtureDirectory = fixtureDirectory
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in self?.enforceLimits() }
    }

    deinit {
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
    }

    var protectedWindowIDs: Set<CGWindowID> {
        items.reduce(into: Set<CGWindowID>()) { ids, item in
            ids.formUnion(item.preview?.protectedWindowIDs ?? [])
        }
    }

    var editorWindowIDs: Set<CGWindowID> {
        items.reduce(into: Set<CGWindowID>()) { $0.formUnion($1.editor?.protectedWindowIDs ?? []) }
    }

    @discardableResult
    func add(_ capture: Capture, id: UUID = UUID(),
             defaultAction: ScreenshotDefaultAction = .none, edited: Bool = false) -> UUID {
        if let existing = items.first(where: { $0.id == id }) {
            existing.editor?.bringForward()
            existing.preview?.bringForward()
            return id
        }
        let item = Item(id: id, capture: capture)
        item.revision = edited ? 1 : 0
        items.append(item)
        showPreview(item, defaultAction: defaultAction)
        if defaultAction == .edit { edit(item) }
        enforceLimits()
        return id
    }

    func openEditor(id: UUID) {
        if let item = items.first(where: { $0.id == id }) { edit(item) }
    }

    func closeAll() {
        stopping = true
        let closing = items
        for item in closing {
            item.preview?.close()
            item.editor?.close()
        }
        items.removeAll()
        stopping = false
    }

    private func showPreview(_ item: Item, defaultAction: ScreenshotDefaultAction = .none) {
        let preview = ScreenshotQuickPreviewController(
            capture: item.capture, strings: FeatureStrings.screenshot(L10n.shared.language),
            defaultAction: defaultAction, preferences: preferences, dragDirectory: fixtureDirectory,
            action: { [weak self, weak item] action in
                guard let self, let item else { return [] }
                if action == .edit { self.edit(item); return [.edit] }
                return self.output(item.id, item.capture, action)
            },
            share: { [weak self, weak item] duration, completion in
                guard let self, let item else { completion(nil); return }
                self.share(item.capture, duration, completion)
            },
            shareFile: { [weak self, weak item] in
                guard let self, let item else { return nil }
                return self.shareFile(item.capture)
            },
            onClose: { [weak self, weak item] in
                guard let item else { return }
                self?.removePreview(item)
            })
        preview.interactionEnded = { [weak self] in self?.enforceLimits() }
        item.preview = preview
        preview.show(inNotch: false)
        layout()
    }

    private func edit(_ item: Item) {
        guard item.editor == nil else { item.editor?.bringForward(); return }
        let editor = ScreenshotEditorController(capture: item.capture,
                                                preferences: preferences,
                                                fixtureDirectory: fixtureDirectory, flattened: item.revision > 0)
        item.editor = editor
        editor.onCommit = { [weak self, weak item] export in
            guard let self, let item else { return }
            item.capture = Capture(image: export.image, scale: export.scale,
                                   anchorRect: item.capture.anchorRect)
            item.revision += 1
            self.committed(item.id, item.capture, item.revision)
        }
        editor.onClose = { [weak self, weak item] in
            guard let self, let item else { return }
            item.editor = nil
            if !self.stopping { self.showPreview(item); self.enforceLimits() }
            if self.fixtureDirectory == nil { WindowActivationPolicy.release() }
        }
        item.preview?.close()
        if fixtureDirectory == nil { WindowActivationPolicy.retain() }
        editor.show()
    }

    private func removePreview(_ item: Item) {
        item.preview = nil
        guard !stopping, item.editor == nil else { return }
        items.removeAll { $0 === item }
        dismissed(item.id)
        layout()
    }

    private func enforceLimits() {
        let candidates = ScreenshotPreviewPolicy.evictionCandidates(items: items.map {
            ($0.id, $0.capture.image.bytesPerRow * $0.capture.image.height, $0.active)
        })
        for id in candidates { items.first { $0.id == id }?.preview?.close() }
        let displays = Dictionary(grouping: items.filter { $0.preview != nil }) { $0.preview!.displayID }
        for captures in displays.values {
            let capacity = captures.map { $0.preview!.visibleCapacity }.min() ?? 1
            let excess = max(0, captures.count - capacity)
            for item in captures.filter({ !$0.active }).prefix(excess) { item.preview?.close() }
        }
        layout()
    }

    private func layout() {
        var indexes: [CGDirectDisplayID: Int] = [:]
        let counts = Dictionary(grouping: items.compactMap(\.preview), by: \.displayID).mapValues(\.count)
        for item in items.reversed() {
            guard let preview = item.preview else { continue }
            let display = preview.displayID
            let index = indexes[display, default: 0]
            preview.setStackIndex(index, count: counts[display, default: 1])
            indexes[display] = index + 1
        }
    }
}

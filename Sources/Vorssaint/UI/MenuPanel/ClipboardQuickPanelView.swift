// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The primary library is a horizontal timeline. The notch remains a compact
/// entry point into this same library, with the same capture and privacy rules.
struct ClipboardQuickPanelView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var history = ClipboardHistoryService.shared
    @FocusState private var searchFocused: Bool
    @FocusState private var collectionsFocused: Bool
    @State private var editingCollection: ClipboardCollection?
    @State private var showsCollectionEditor = false
    @State private var fullPreviewEntry: ClipboardHistoryEntry?
    @State private var renameEntry: ClipboardHistoryEntry?
    @State private var renameDraft = ""
    @State private var previewIsEditing = false
    @State private var showsClearConfirmation = false
    private var text: ClipboardFeatureStrings { FeatureStrings.clipboard(l10n.language) }
    private var libraryText: ClipboardLibraryStrings { .init(language: l10n.language) }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            collections
            Divider()
            HStack(spacing: 0) {
                timeline
                if history.quickPreviewPresented {
                    Divider()
                    ClipboardEntryPreviewSidebar(text: text, entry: history.selectedQuickEntry,
                        isEditing: $previewIsEditing, onClose: { history.setQuickPreviewPresented(false) })
                        .frame(width: 320)
                }
            }
            Divider()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .ignoresSafeArea()
        .onAppear { searchFocused = true }
        .onChange(of: searchFocused) { _, focused in
            if focused { history.keyboardFocus = .search; history.quickSelectionIsVisible = false }
        }
        .onChange(of: history.collectionFocusRequest) { _, _ in searchFocused = false; collectionsFocused = true }
        .onChange(of: history.searchFocusRequest) { _, _ in searchFocused = true }
        .onChange(of: history.quickSelectionIsVisible) { _, selected in if selected { searchFocused = false } }
        .onChange(of: history.quickWindowPresentationID) { _, _ in searchFocused = true }
        .onChange(of: history.editRequest) { _, _ in history.setQuickPreviewPresented(true); previewIsEditing = true }
        .onChange(of: history.renameRequest) { _, _ in beginRename(history.selectedQuickEntry) }
        .sheet(isPresented: $showsCollectionEditor) { collectionEditor }
        .sheet(item: $fullPreviewEntry) { ClipboardLargePreview(entry: $0) }
        .onChange(of: history.fullPreviewRequest) { _, _ in fullPreviewEntry = history.selectedQuickEntry }
        .sheet(item: $renameEntry) { entry in renameEditor(entry) }
        .confirmationDialog(text.clearRecent, isPresented: $showsClearConfirmation) {
            Button(text.clearRecent, role: .destructive) { history.clearRecent() }
        } message: { Text(libraryText.retentionWarning) }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Label(text.title, systemImage: "doc.on.clipboard.fill")
                .font(.system(size: 15, weight: .semibold))
            TextField(text.search, text: $history.quickQuery)
                .textFieldStyle(.roundedBorder).focused($searchFocused)
                .frame(minWidth: 160, maxWidth: 360)
                .help("type:image  app:Safari  after:2026-01-01  before:2026-12-31")
            Spacer(minLength: 0)
            Button(history.pauseIsActive ? libraryText.resume : libraryText.pause) {
                history.pause(for: history.pauseIsActive ? nil : .infinity)
            }.controlSize(.small)
            Button { history.toggleQuickPreview() } label: {
                Image(systemName: history.quickPreviewPresented ? "sidebar.right" : "eye")
            }.help(text.previewLabel).accessibilityLabel(text.previewLabel)
            Button { history.hideHistoryWindow() } label: { Image(systemName: "xmark") }
                .help(l10n.s.menuClose).accessibilityLabel(l10n.s.menuClose)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)
    }

    private var collections: some View {
        HStack(spacing: 10) {
            collectionTab(text.recent, id: nil, color: .accentColor).focused($collectionsFocused)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(history.collections) { collection in
                        collectionTab(collection.name, id: collection.id, color: ClipboardCardPalette.color(collection.color))
                            .contextMenu { collectionActions(collection) }
                            .onDrop(of: [ClipboardCardPalette.dragType], isTargeted: nil) { providers in
                                receiveCollectionDrop(providers, collection: collection)
                            }
                    }
                }
            }
            Button { editingCollection = nil; showsCollectionEditor = true } label: {
                Image(systemName: "plus.circle")
            }.buttonStyle(.borderless).help(libraryText.newCollection).accessibilityLabel(libraryText.newCollection)
        }.padding(.horizontal, 20).padding(.bottom, 12)
    }

    private func collectionTab(_ title: String, id: UUID?, color: Color) -> some View {
        Button { history.selectedCollectionID = id } label: {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(history.selectedCollectionID == id ? color.opacity(0.16) : .clear,
                        in: Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(history.selectedCollectionID == id ? .isSelected : [])
    }

    private var timeline: some View {
        GeometryReader { geometry in
            if history.quickResults.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 32, weight: .light))
                    Text(history.libraryReady ? (history.entries.isEmpty ? text.empty : text.noResults) : libraryText.saving)
                }.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 14) {
                            ForEach(Array(history.quickResults.enumerated()), id: \.element.id) { index, entry in
                                ClipboardHistoryCard(entry: entry, number: history.visibleShortcutIDs.firstIndex(of: entry.id).map { $0 + 1 },
                                    selected: history.quickSelectionIsVisible && history.selectedQuickEntryID == entry.id,
                                    compact: geometry.size.height < 220,
                                    onSelect: { select(entry) }, onRename: { beginRename(entry) })
                                    .frame(width: geometry.size.height < 220 ? 210 : 246)
                                    .id(entry.id)
                                    .background(GeometryReader { card in
                                        Color.clear.preference(key: ClipboardCardFrames.self,
                                            value: [entry.id: card.frame(in: .named("clipboardTimeline"))])
                                    })
                            }
                        }.padding(16).frame(height: geometry.size.height)
                    }
                    .coordinateSpace(name: "clipboardTimeline")
                    .onPreferenceChange(ClipboardCardFrames.self) { frames in
                        let visible = frames.filter { $0.value.maxX > 0 && $0.value.minX < geometry.size.width }
                            .sorted { $0.value.minX < $1.value.minX }.prefix(9).map(\.key)
                        if history.visibleShortcutIDs != visible { history.visibleShortcutIDs = visible }
                    }
                    .onChange(of: history.quickSelectionIndex) { _, _ in scrollSelection(proxy) }
                    .onChange(of: history.quickSelectionIsVisible) { _, _ in scrollSelection(proxy) }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let error = history.storageError {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).lineLimit(2)
            } else {
                Label(history.isSaving ? libraryText.saving : libraryText.saved,
                      systemImage: history.isSaving ? "arrow.triangle.2.circlepath" : "checkmark.shield")
            }
            Text("\(history.quickResults.count)").monospacedDigit()
            Spacer(minLength: 4)
            if history.quickBatchCount > 0 {
                Button(String(format: text.pasteSelectedFormat, history.quickBatchCount)) { history.copySelectedQuickEntry() }
                Button(text.clearSelection) { history.clearQuickBatchSelection() }
            } else {
                Text(AXIsProcessTrusted() ? "← →   ␣   ↩   ⇧↩   ⌘1–9" : libraryText.copyFallback).lineLimit(1)
            }
            Button { showsClearConfirmation = true } label: { Image(systemName: "trash") }
                .help(text.clearRecent).accessibilityLabel(text.clearRecent)
        }.font(.system(size: 10.5)).foregroundStyle(.secondary)
            .buttonStyle(.borderless).padding(.horizontal, 20).padding(.vertical, 10)
    }

    private func select(_ entry: ClipboardHistoryEntry) {
        if NSEvent.modifierFlags.contains(.command) { history.toggleQuickBatchSelection(entry) }
        else if NSEvent.modifierFlags.contains(.shift) { history.extendQuickBatchSelection(to: entry) }
        else if let index = history.quickResults.firstIndex(where: { $0.id == entry.id }) {
            history.quickSelectionIndex = index
            history.keyboardFocus = .results
            history.quickSelectionIsVisible = true
            searchFocused = false
        }
    }

    private func beginRename(_ entry: ClipboardHistoryEntry?) {
        guard let entry else { return }
        renameDraft = entry.title
        renameEntry = entry
    }

    private func scrollSelection(_ proxy: ScrollViewProxy) {
        guard history.quickSelectionIsVisible, let id = history.selectedQuickEntryID else { return }
        proxy.scrollTo(id)
    }

    @ViewBuilder private func collectionActions(_ collection: ClipboardCollection) -> some View {
        Button(libraryText.rename) { editingCollection = collection; showsCollectionEditor = true }
        Button(text.moveUp) { history.moveCollection(collection, delta: -1) }
        Button(text.moveDown) { history.moveCollection(collection, delta: 1) }
        Button(text.delete, role: .destructive) { history.deleteCollection(collection) }
    }

    private var collectionEditor: some View {
        ClipboardCollectionEditor(collection: editingCollection, onSave: { name, color in
            if let editingCollection { history.updateCollection(editingCollection, name: name, color: color) }
            else { history.createCollection(name: name, color: color) }
            showsCollectionEditor = false
        }, onCancel: { showsCollectionEditor = false })
    }

    private func renameEditor(_ entry: ClipboardHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(libraryText.rename).font(.headline)
            TextField(libraryText.name, text: $renameDraft)
            HStack {
                Button(l10n.s.menuClose) { renameEntry = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(libraryText.apply) { history.rename(entry, title: renameDraft); renameEntry = nil }
                    .keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 340)
    }

    private func receiveCollectionDrop(_ providers: [NSItemProvider], collection: ClipboardCollection) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: ClipboardCardPalette.dragType) { data, _ in
            guard let data, let string = String(data: data, encoding: .utf8), let id = UUID(uuidString: string) else { return }
            DispatchQueue.main.async {
                if let entry = history.entries.first(where: { $0.id == id }) { history.addToCollection(entry, id: collection.id) }
            }
        }
        return true
    }
}

struct ClipboardCollectionEditor: View {
    let collection: ClipboardCollection?
    let onSave: (String, Int) -> Void
    let onCancel: () -> Void
    @State private var name = ""
    @State private var color = 0
    private var strings: ClipboardLibraryStrings { .current }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(collection == nil ? strings.newCollection : strings.rename).font(.headline)
            TextField(strings.name, text: $name).textFieldStyle(.roundedBorder)
            HStack(spacing: 12) {
                Text(strings.color)
                ForEach(0..<6) { value in
                    Button { color = value } label: {
                        Circle().fill(ClipboardCardPalette.color(value)).frame(width: 24, height: 24)
                            .overlay { if color == value { Image(systemName: "checkmark").foregroundStyle(.white).font(.caption.bold()) } }
                    }.buttonStyle(.plain).accessibilityLabel("\(strings.color) \(value + 1)")
                }
            }
            HStack {
                Button(L10n.shared.s.menuClose, action: onCancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button(strings.apply) { onSave(name, color) }.keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 360)
            .onAppear { name = collection?.name ?? ""; color = collection?.color ?? 0 }
    }
}

private struct ClipboardCardFrames: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

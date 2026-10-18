// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// On-demand inspector for the selected clipboard entry. It keeps the full
/// content selectable and editable without permanently taking space from the
/// history list.
struct ClipboardEntryPreview: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var history = ClipboardHistoryService.shared
    var text: ClipboardFeatureStrings
    var entry: ClipboardHistoryEntry?
    @Binding var isEditing: Bool
    var onClose: () -> Void
    @State private var draft = ""
    @State private var editingEntryID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            previewHeader
            Divider()
            if let entry {
                if editingEntryID == entry.id {
                    textEditor(entry)
                } else if entry.kind == .text {
                    ClipboardRichPreview(entry: entry)
                } else {
                    contentScrollView(entry)
                }
                Divider()
                previewFooter(entry)
            } else {
                emptyState
            }
        }
        .onChange(of: entry?.id) { _, newID in
            if editingEntryID != nil, editingEntryID != newID {
                cancelEditing()
            }
        }
        .onChange(of: isEditing) { _, editing in
            if editing, let entry, entry.kind == .text, editingEntryID == nil { beginEditing(entry) }
            else if !editing, editingEntryID != nil { cancelEditing() }
        }
        .onAppear { if isEditing, let entry, entry.kind == .text { beginEditing(entry) } }
        .onChange(of: history.cancelEditRequest) { _, _ in cancelEditing() }
        .onDisappear { cancelEditing() }
    }

    private var previewHeader: some View {
        HStack(spacing: 8) {
            Label(text.previewLabel, systemImage: "doc.text.magnifyingglass")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(l10n.s.menuClose)
            .accessibilityLabel(l10n.s.menuClose)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(HUDBackdrop())
    }

    private func contentScrollView(_ entry: ClipboardHistoryEntry) -> some View {
        ScrollView {
            previewContent(entry)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxHeight: .infinity)
    }

    private func textEditor(_ entry: ClipboardHistoryEntry) -> some View {
        PlainTextEditor(text: $draft, fontSize: 12, onCancel: cancelEditing) { view in
            view.setAccessibilityLabel(text.edit)
            DispatchQueue.main.async { [weak view] in
                guard let view else { return }
                view.window?.makeFirstResponder(view)
            }
        }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1)
            )
            .padding(12)
            .accessibilityLabel(text.edit)
    }

    @ViewBuilder
    private func previewContent(_ entry: ClipboardHistoryEntry) -> some View {
        switch entry.kind {
        case .text:
            // Standard text selection lets someone copy only the fragment
            // they need; the window monitor leaves ⌘C with this view.
            Text(entry.text)
                .font(.system(size: 12))
                .textSelection(.enabled)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        case .image:
            imagePreview(entry)
        case .files:
            ClipboardFilesPreview(entry: entry)
        }
    }

    @ViewBuilder
    private func imagePreview(_ entry: ClipboardHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let name = entry.imageFile {
                ClipboardThumbnailImage(source: .stored(name: name),
                                        aspectRatio: entry.imageAspectRatio)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            Text("\(text.imageEntryLabel) · \(entry.imageDimensionsLabel)")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var emptyState: some View {
        Image(systemName: "doc.on.clipboard")
            .font(.system(size: 22, weight: .light))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func previewFooter(_ entry: ClipboardHistoryEntry) -> some View {
        HStack(spacing: 6) {
            if entry.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.accentColor)
            }
            Text(entry.copiedAt.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
            Spacer()
            previewActions(entry)
        }
        .controlSize(.mini)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(HUDBackdrop())
    }

    @ViewBuilder private func previewActions(_ entry: ClipboardHistoryEntry) -> some View {
        if editingEntryID == entry.id {
            Button(text.cancel) {
                cancelEditing()
            }
            Button(text.save) {
                saveEditing(entry)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!ClipboardHistoryEditing.canSave(original: entry.text, draft: draft))
        } else {
            Button { ClipboardHistoryService.shared.togglePin(entry) } label: {
                Image(systemName: entry.isPinned ? "pin.slash" : "pin")
            }
            .help(entry.isPinned ? text.unpin : text.pin)
            .accessibilityLabel(entry.isPinned ? text.unpin : text.pin)
            if entry.kind == .text {
                Button(ClipboardLibraryStrings.current.editCopy) {
                    beginEditing(entry)
                }
            }
            Button(text.copy) {
                ClipboardHistoryService.shared.copyOnlyQuickEntry(entry)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func beginEditing(_ entry: ClipboardHistoryEntry) {
        draft = entry.text
        editingEntryID = entry.id
        isEditing = true
    }

    private func cancelEditing() {
        editingEntryID = nil
        draft = ""
        isEditing = false
    }

    private func saveEditing(_ entry: ClipboardHistoryEntry) {
        guard ClipboardHistoryService.shared.updateText(entry, to: draft) else { return }
        cancelEditing()
    }
}

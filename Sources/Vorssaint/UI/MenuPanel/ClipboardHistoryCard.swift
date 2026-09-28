// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import UniformTypeIdentifiers

enum ClipboardCardPalette {
    static func color(_ index: Int) -> Color { [.blue, .purple, .pink, .orange, .green, .teal][abs(index % 6)] }
    static let dragType = "io.github.xztyle.aster.clipboard-entry"
}

struct ClipboardHistoryCard: View {
    let entry: ClipboardHistoryEntry
    let number: Int?
    let selected: Bool
    let compact: Bool
    let onSelect: () -> Void
    let onRename: () -> Void
    @ObservedObject private var history = ClipboardHistoryService.shared
    @State private var hovered = false
    private var text: ClipboardFeatureStrings { FeatureStrings.clipboard(L10n.shared.language) }
    private var strings: ClipboardLibraryStrings { .current }
    private var tint: Color {
        switch entry.kind {
        case .image: return .purple
        case .files: return .orange
        case .text: return entry.color != nil ? .pink : (webURL != nil ? .blue : .teal)
        }
    }
    private var webURL: URL? {
        guard entry.kind == .text, let url = URL(string: entry.text.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(url.scheme ?? ""), url.host != nil else { return nil }
        return url
    }
    private var title: String {
        if !entry.title.isEmpty { return entry.title }
        if let webURL { return webURL.host ?? "" }
        switch entry.kind {
        case .image: return text.imageEntryLabel
        case .files: return entry.fileNames.first ?? strings.unavailable
        case .text: return entry.color != nil ? strings.color : text.title
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            preview.padding(compact ? 12 : 16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            footer
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 13))
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(selected || history.isQuickBatchSelected(entry) ? Color.accentColor : Color.primary.opacity(0.09), lineWidth: selected ? 3 : 1) }
        .shadow(color: .black.opacity(hovered ? 0.12 : 0.06), radius: 7, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: 13))
        .onHover { hovered = $0 }
        .onTapGesture(count: 2) { history.copyQuickEntry(entry) }
        .onTapGesture(perform: onSelect)
        .contextMenu { actions }
        .onDrag { dragProvider() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(entry.preview), \(entry.sourceApp ?? strings.unknownApp)")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction { onSelect() }
        .accessibilityAction(named: Text(text.copy)) { history.copyOnlyQuickEntry(entry) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.kind == .image ? "photo" : entry.kind == .files ? "folder.fill" : webURL == nil ? "text.alignleft" : "link")
            Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 0)
            if entry.isPinned { Image(systemName: "pin.fill").font(.caption2) }
            if let number { Text("⌘\(number)").font(.system(size: 10, weight: .medium, design: .rounded)) }
        }.foregroundStyle(tint).padding(.horizontal, 13).padding(.vertical, 11).background(tint.opacity(0.11))
    }

    @ViewBuilder private var preview: some View {
        switch entry.kind {
        case .image:
            if let name = entry.imageFile {
                ClipboardThumbnailImage(source: .stored(name: name), aspectRatio: entry.imageAspectRatio)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else { unavailable }
        case .files:
            VStack(alignment: .leading, spacing: 10) {
                if let path = entry.filePaths.first, FileManager.default.fileExists(atPath: path) {
                    Image(nsImage: ClipboardImageStore.fileIcon(atPath: path)).resizable().scaledToFit().frame(height: compact ? 28 : 54)
                } else { unavailable }
                Text(entry.fileNames.joined(separator: "\n")).font(.system(size: 13, weight: .medium)).lineLimit(compact ? 2 : 5)
                if !compact { Text(entry.filePaths.first ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle) }
            }
        case .text:
            if let color = entry.color {
                VStack(alignment: .leading, spacing: 12) {
                    ClipboardColorSwatch(color: color, size: compact ? 34 : 80)
                    Text(entry.text).font(.system(size: 14, weight: .medium, design: .monospaced))
                }
            } else {
                Text(String(entry.text.prefix(2_000))).font(.system(size: compact ? 12 : 14))
                    .lineSpacing(4).foregroundStyle(webURL == nil ? Color.primary : tint)
                    .frame(maxWidth: .infinity, alignment: .topLeading).clipped()
            }
        }
    }

    private var unavailable: some View { Label(strings.unavailable, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary).font(.caption) }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(entry.sourceApp ?? strings.unknownApp).lineLimit(1)
                Spacer(minLength: 4)
                Text(entry.copiedAt.formatted(date: .abbreviated, time: .shortened)).lineLimit(1)
            }
            if !compact {
                HStack {
                    Text(entry.kind == .image ? entry.imageDimensionsLabel : entry.kind == .files ? "\(entry.filePaths.count)" : "\(entry.text.count)")
                    if !entry.representations.isEmpty { Image(systemName: "textformat") }
                    Spacer()
                    Button { history.togglePin(entry) } label: { Image(systemName: entry.isPinned ? "pin.slash" : "pin") }
                        .buttonStyle(.borderless).help(entry.isPinned ? text.unpin : text.pin)
                }
            }
        }.font(.system(size: 10)).foregroundStyle(.secondary).padding(12)
    }

    @ViewBuilder private var actions: some View {
        Button(text.copy) { history.copyOnlyQuickEntry(entry) }
        Button(strings.plainText) { history.pastePlain(entry) }.disabled(entry.kind != .text)
        Button(text.previewLabel) { onSelect(); history.setQuickPreviewPresented(true) }
        Button(strings.rename, action: onRename)
        if entry.kind == .text {
            Button(strings.editCopy) { onSelect(); history.editRequest = UUID() }
        } else if entry.kind == .image, AppFeature.screenshot.isAvailable {
            Button(text.edit) { history.editImage(entry) }
        }
        Menu(strings.collections) {
            ForEach(history.collections) { collection in
                Button(collection.name) { history.addToCollection(entry, id: collection.id) }
            }
        }
        Button(entry.isPinned ? text.unpin : text.pin) { history.togglePin(entry) }
        if history.selectedCollectionID != nil {
            Button(text.moveUp) { history.reorderInCollection(entry, delta: -1) }
            Button(text.moveDown) { history.reorderInCollection(entry, delta: 1) }
        }
        Divider()
        Button(text.delete, role: .destructive) { history.remove(entry) }
    }

    private func dragProvider() -> NSItemProvider {
        let provider: NSItemProvider
        if entry.kind == .files, let path = entry.filePaths.first {
            provider = NSItemProvider(contentsOf: URL(fileURLWithPath: path)) ?? NSItemProvider()
        } else { provider = NSItemProvider() }
        provider.registerDataRepresentation(forTypeIdentifier: ClipboardCardPalette.dragType, visibility: .ownProcess) { completion in
            completion(Data(entry.id.uuidString.utf8), nil); return nil
        }
        if entry.kind == .text {
            provider.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all) { completion in
                completion(Data(entry.text.utf8), nil); return nil
            }
        }
        for (type, name) in entry.representations {
            provider.registerDataRepresentation(forTypeIdentifier: type, visibility: .all) { completion in
                completion(ClipboardImageStore.imageData(named: name), nil); return nil
            }
        }
        if let name = entry.imageFile {
            provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
                completion(ClipboardImageStore.imageData(named: name), nil); return nil
            }
        }
        return provider
    }
}

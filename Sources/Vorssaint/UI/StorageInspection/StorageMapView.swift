// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import SwiftUI

struct StorageMapView: View {
    let items: [StorageMapItem]
    let selected: Set<String>
    @Binding var focused: String?
    let onOpen: (StorageMapItem) -> Void
    let onSelect: (StorageMapItem, Bool) -> Void
    let onReveal: (StorageMapItem) -> Void
    let onUp: () -> Void
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    private var text: StorageMapStrings { .init(language: l10n.language) }
    private var storageText: StorageInspectionStrings { .init(language: l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text[.title]).font(.headline)
            GeometryReader { geometry in
                let circles = StorageMapLayout.circles(items, size: geometry.size)
                ZStack {
                    Color.clear.contentShape(Rectangle()).onTapGesture(count: 2, perform: onUp)
                    ForEach(circles) { circle in
                        if let item = items.first(where: { $0.id == circle.id }) {
                            bubble(item, diameter: circle.radius * 2).position(circle.center)
                        }
                    }
                    if circles.isEmpty { Text(text[.empty]).foregroundStyle(.secondary) }
                }
            }.frame(height: 260)
            HStack {
                if let item = items.first(where: { $0.id == focused }) {
                    Text(title(item)).lineLimit(1)
                    Spacer()
                    Text(bytes(item.bytes)).monospacedDigit()
                } else { Text(text[.note]).foregroundStyle(.secondary) }
            }.font(.caption).frame(height: 28)
        }.padding(14).background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
    }

    private func bubble(_ item: StorageMapItem, diameter: Double) -> some View {
        let active = focused == item.id || selected.contains(item.id)
        return Button { onOpen(item) } label: {
            Circle().fill(color(item).opacity(active ? 0.3 : 0.14))
                .overlay { Circle().strokeBorder(color(item).opacity(active ? 1 : 0.5), lineWidth: active || contrast == .increased ? 2 : 1) }
                .overlay { if diameter >= 58 { bubbleLabel(item, diameter: diameter) } }
                .frame(width: diameter, height: diameter).contentShape(Circle())
        }.buttonStyle(.plain)
            .help("\(item.url?.path ?? title(item))\n\(bytes(item.bytes))")
            .accessibilityLabel("\(title(item)), \(bytes(item.bytes))")
            .accessibilityAddTraits(selected.contains(item.id) ? .isSelected : [])
            .onHover { hover in focused = hover ? item.id : (focused == item.id ? nil : focused) }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: active)
            .contextMenu { itemActions(item) }
    }

    private func bubbleLabel(_ item: StorageMapItem, diameter: Double) -> some View {
        VStack(spacing: 4) {
            Image(systemName: item.kind == .folder ? "folder.fill" : item.kind == .other ? "ellipsis" : "doc.fill")
            Text(title(item)).lineLimit(1).truncationMode(.middle)
            if diameter > 100 { Text(bytes(item.bytes)).font(.caption2).monospacedDigit() }
        }.font(.system(size: min(13, max(9, diameter / 12)), weight: .medium))
            .foregroundStyle(.primary).frame(width: diameter * 0.72)
    }

    @ViewBuilder private func itemActions(_ item: StorageMapItem) -> some View {
        if item.kind == .file {
            Toggle(storageText[.selected], isOn: Binding(get: { selected.contains(item.id) },
                                                       set: { onSelect(item, $0) }))
            Button(storageText[.review]) { onOpen(item) }
        }
        if item.url != nil { Button(storageText[.reveal]) { onReveal(item) } }
    }

    private func color(_ item: StorageMapItem) -> Color { item.kind == .folder ? .accentColor : .secondary }
    private func title(_ item: StorageMapItem) -> String { item.url?.lastPathComponent ?? "\(text[.other]) (\(item.count))" }
    private func bytes(_ count: Int64) -> String { ByteCountFormatter.string(fromByteCount: count, countStyle: .file) }
}

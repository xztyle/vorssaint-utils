// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import Quartz

struct ClipboardLargePreview: View {
    let entry: ClipboardHistoryEntry
    @Environment(\.dismiss) private var dismiss
    private var strings: ClipboardFeatureStrings { FeatureStrings.clipboard(L10n.shared.language) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(entry.title.isEmpty ? strings.previewLabel : entry.title).font(.headline)
                Spacer()
                Button(L10n.shared.s.menuClose) { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(16)
            Divider()
            if entry.kind == .text { ClipboardRichPreview(entry: entry) }
            else if let url = previewURL, FileManager.default.fileExists(atPath: url.path) {
                ClipboardQuickLook(url: url)
            } else {
                Label(ClipboardLibraryStrings.current.unavailable, systemImage: "exclamationmark.triangle")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.frame(width: 720, height: 560)
    }

    private var previewURL: URL? {
        if let name = entry.imageFile, let directory = ClipboardImageStore.directory {
            return try? ClipboardLibraryArchive.safeAsset(name, in: directory)
        }
        return entry.filePaths.first.map { URL(fileURLWithPath: $0) }
    }
}

private struct ClipboardQuickLook: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> QLPreviewView { QLPreviewView(frame: .zero, style: .normal)! }
    func updateNSView(_ view: QLPreviewView, context: Context) { view.previewItem = url as NSURL }
}

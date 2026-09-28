// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct ClipboardRichPreview: View {
    let entry: ClipboardHistoryEntry
    @State private var plain = false

    var body: some View {
        VStack(spacing: 0) {
            if !entry.representations.isEmpty {
                Toggle(isOn: $plain) { Image(systemName: "textformat") }
                    .toggleStyle(.switch).controlSize(.small).padding(10)
                    .help(ClipboardLibraryStrings.current.plainText)
            }
            if !plain, let rich = attributedText {
                ClipboardAttributedPreview(value: rich)
            } else { ClipboardTextPreview(text: entry.text) }
        }
    }

    private var attributedText: NSAttributedString? {
        for (type, format) in [(NSPasteboard.PasteboardType.rtfd, NSAttributedString.DocumentType.rtfd), (.rtf, .rtf)] {
            if let name = entry.representations[type.rawValue], let data = ClipboardImageStore.imageData(named: name),
               let value = try? NSAttributedString(data: data, options: [.documentType: format], documentAttributes: nil) { return value }
        }
        // HTML is retained for paste, but never rendered here: external images
        // in a copied web fragment must not make network requests from history.
        return nil
    }
}

private struct ClipboardAttributedPreview: NSViewRepresentable {
    let value: NSAttributedString

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        let view = NSTextView()
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainerInset = NSSize(width: 12, height: 12)
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = view
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        view.textStorage?.setAttributedString(value)
    }
}

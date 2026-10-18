// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import SwiftUI
import Quartz

struct ClipboardFilesPreview: View {
    let entry: ClipboardHistoryEntry
    private var text: ClipboardFeatureStrings { FeatureStrings.clipboard(L10n.shared.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if entry.filePaths.count == 1, let path = entry.filePaths.first {
                singleFile(path)
            } else {
                Text(String(format: text.fileCountFormat, entry.filePaths.count))
                    .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.secondary)
                ForEach(entry.filePaths, id: \.self) { fileSummary($0) }
            }
            Text(entry.filePaths.joined(separator: "\n"))
                .font(.system(size: 10.5, design: .monospaced)).textSelection(.enabled)
                .lineSpacing(2).foregroundStyle(.secondary).padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        }.frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private func singleFile(_ path: String) -> some View {
        if ClipboardImageStore.isImageFile(atPath: path) {
            ClipboardThumbnailImage(source: .file(path: path),
                aspectRatio: ClipboardImageStore.imageAspectRatio(atPath: path))
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            let parts = [text.imageEntryLabel, ClipboardImageStore.imageDimensionsLabel(atPath: path),
                         ClipboardImageStore.fileSizeString(atPath: path)].compactMap { $0 }
            Text(parts.joined(separator: " · ")).font(.system(size: 10.5)).foregroundStyle(.secondary)
        } else {
            if FileManager.default.fileExists(atPath: path) {
                ClipboardFileQuickLook(url: URL(fileURLWithPath: path)).frame(height: 200)
            } else {
                Label(ClipboardLibraryStrings.current.unavailable, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
            fileSummary(path)
        }
    }

    private func fileSummary(_ path: String) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable().frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text((path as NSString).lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(2)
                if let size = ClipboardImageStore.fileSizeString(atPath: path) {
                    Text(size).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct ClipboardFileQuickLook: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> NSView { QLPreviewView(frame: .zero, style: .normal) ?? NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        (view as? QLPreviewView)?.previewItem = url as NSURL
    }
}

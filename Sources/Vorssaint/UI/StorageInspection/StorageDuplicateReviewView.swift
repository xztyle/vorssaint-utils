// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct StorageDuplicateReviewView: View {
    @ObservedObject private var service = StorageInspectionService.shared
    @State private var shown = 50
    private var text: StorageInspectionStrings { .current }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                Text(text[.chooseKeeper]).foregroundStyle(.secondary)
                ForEach(service.duplicates.groups.prefix(shown)) { group in StorageDuplicateGroupView(group: group) }
                if service.duplicates.groups.count > shown { Button(text[.more]) { shown += 50 } }
                ForEach(service.duplicates.issues) { issue in Text("\(text[.partial]): \(issue.path)").font(.caption).textSelection(.enabled) }
            }
        }
    }
}

private struct StorageDuplicateGroupView: View {
    let group: StorageDuplicateGroup
    @State private var shown = 50
    @ObservedObject private var service = StorageInspectionService.shared
    private var text: StorageInspectionStrings { .current }
    var body: some View {
        GroupBox("\(group.files.count) · \(ByteCountFormatter.string(fromByteCount: group.files[0].logicalBytes, countStyle: .file))") {
            VStack(alignment: .leading) {
                ForEach(group.files.prefix(shown)) { file in
                    HStack(alignment: .top) {
                        StorageFileRow(file: file, allowsSelection: group.keeperID != nil && group.keeperID != file.id)
                        Button { service.keep(file, group: group.id) } label: {
                            Label(StorageInspectionStrings.current[.keeper], systemImage: group.keeperID == file.id ? "checkmark.shield.fill" : "shield")
                        }
                        .accessibilityLabel("\(text[.keeper]) · \(file.url.lastPathComponent)")
                        .accessibilityHint(file.url.path)
                        .disabled(service.busy)
                    }
                }
                if group.files.count > shown { Button(text[.more]) { shown += 50 } }
            }
        }.accessibilityElement(children: .contain)
    }
}

struct StorageTrashReviewView: View {
    @ObservedObject private var service = StorageInspectionService.shared
    @Environment(\.dismiss) private var dismiss
    private var text: StorageInspectionStrings { .current }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(text[.review]).font(.title2.bold())
            Text(text[.trashWarning]).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(service.selectedFiles) { file in Text(file.url.path).font(.callout).textSelection(.enabled) }
                    ForEach(service.duplicates.groups.filter { $0.files.contains { service.selection.contains($0.id) } }) { group in
                        Text("\(text[.keeper]): \(group.keeperID ?? text[.chooseKeeper])").textSelection(.enabled)
                    }
                }
            }
            HStack {
                Button(text[.cancel]) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(text[.trash], role: .destructive) { service.trashSelected(); dismiss() }
                    .disabled(!StorageInspectionPolicy.removalsAllowed(service.selection, groups: service.duplicates.groups))
            }
        }.padding(24).frame(width: 640, height: 450)
    }
}

struct StorageRecoveryView: View {
    @ObservedObject private var service = StorageInspectionService.shared
    private var text: StorageInspectionStrings { .current }
    var body: some View {
        if !service.receipts.isEmpty {
            GroupBox(text[.recovery]) {
                ForEach(service.receipts) { receipt in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(receipt.original.path).font(.caption).textSelection(.enabled)
                        if let url = receipt.trash {
                            Button("\(text[.reveal]): \(url.path)") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        } else { Text("\(text[.failed]): \(failure(receipt.failure))").foregroundStyle(.orange) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.accessibilityElement(children: .contain)
        }
    }
    private func failure(_ detail: String?) -> String {
        guard let detail, let reason = StorageInspectionFailure(rawValue: detail) else { return detail ?? text[.failed] }
        switch reason {
        case .changed: return text[.changed]
        case .denied, .unavailable: return text[.denied]
        case .cancelled: return text[.cancel]
        case .limit: return text[.partial]
        case .excluded: return text[.skipped]
        case .missingKeeper: return text[.chooseKeeper]
        case .failed: return text[.failed]
        }
    }

}

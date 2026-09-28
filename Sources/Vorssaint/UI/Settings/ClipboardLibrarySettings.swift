// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct ClipboardLibrarySettings: View {
    @ObservedObject private var history = ClipboardHistoryService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var retention = UserDefaults.standard.integer(forKey: DefaultsKey.clipboardRetentionDays)
    private var strings: ClipboardLibraryStrings { .init(language: l10n.language) }
    private var removals: [ClipboardHistoryEntry] { history.retentionRemovals(days: retention) }

    var body: some View {
        Section(strings.collections) {
            Picker(strings.retention, selection: $retention) {
                Text(strings.forever).tag(0)
                ForEach([1, 7, 30, 365], id: \.self) { days in Text("\(days) \(strings.days)").tag(days) }
            }
            HStack {
                Text("\(removals.count) · \(ByteCountFormatter.string(fromByteCount: history.retentionByteCount(days: retention), countStyle: .file))")
                Spacer()
                Button(strings.apply) { history.applyRetention(days: retention) }
                    .disabled(!history.libraryReady)
            }
            Text(strings.retentionWarning).font(.caption).foregroundStyle(.secondary)
            Button(history.pauseIsActive ? strings.resume : strings.pause) {
                history.pause(for: history.pauseIsActive ? nil : .infinity)
            }
            HStack {
                Button(strings.exportLibrary) { history.exportLibrary() }
                Button(strings.restoreLibrary) { history.chooseRestoreLibrary() }
            }.disabled(!history.libraryReady || history.isSaving)
            Text(strings.privateArchive).font(.caption).foregroundStyle(.secondary)
            if let error = history.storageError {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            } else {
                Label(history.isSaving ? strings.saving : strings.saved, systemImage: "internaldrive")
                    .foregroundStyle(.secondary)
            }
            Text("← → · ⌘F · ↩ · ⇧↩ · ⌘1–9 · ␣ · ⌘E · ⌘R").font(.caption.monospaced())
        }
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import QuickLook

struct StorageInspectionView: View {
    @ObservedObject private var service = StorageInspectionService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var tool = 0
    @State private var filter = 0
    @State private var megabytes = max(1, UserDefaults.standard.integer(forKey: DefaultsKey.storageLargeMegabytes))
    @State private var days = max(1, UserDefaults.standard.integer(forKey: DefaultsKey.storageOldDays))
    @State private var folder: URL?
    @State private var shown = 100
    @State private var review = false
    @State private var preview: URL?
    private var text: StorageInspectionStrings { .current }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Picker("", selection: $tool) {
                Text(text[.storage]).tag(0)
                Text(text[.duplicates]).tag(1)
                Text(text[.security]).tag(2)
                Text(text[.malware]).tag(3)
            }.pickerStyle(.segmented).labelsHidden()
            if tool < 2 { fileTools }
            if tool == 0 { storageResults }
            else if tool == 1 { StorageDuplicateReviewView() }
            else { StorageSecurityView(malwareMode: tool == 3) }
            if !service.detail.isEmpty { Text(service.detail).font(.caption).textSelection(.enabled).lineLimit(5) }
            if tool < 2 { footer }
        }
        .padding(22).frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $review) { StorageTrashReviewView() }
        .quickLookPreview($preview)
        .onDisappear { service.cancel() }
        .onChange(of: service.roots) { _, _ in folder = nil; shown = 100 }
        .onChange(of: megabytes) { _, value in save(value, key: DefaultsKey.storageLargeMegabytes) }
        .onChange(of: days) { _, value in save(value, key: DefaultsKey.storageOldDays) }
        .onAppear {
            if UserDefaults.standard.object(forKey: DefaultsKey.storageLargeMegabytes) == nil { megabytes = 100 }
            if UserDefaults.standard.object(forKey: DefaultsKey.storageOldDays) == nil { days = 180 }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(text[.title], systemImage: "internaldrive").font(.title2.bold())
                Spacer()
                if service.busy { Text("\(service.progress)").font(.caption.monospacedDigit()); ProgressView().controlSize(.small); Button(text[.cancel]) { service.cancel() } }
            }
            Text(text[.localOnly]).font(.callout).foregroundStyle(.secondary)
            capacity
        }
    }

    @ViewBuilder private var capacity: some View {
        if let values = try? (service.roots.first ?? URL(fileURLWithPath: "/")).resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
           let total = values.volumeTotalCapacity, let available = values.volumeAvailableCapacity, total > 0 {
            HStack {
                ProgressView(value: Double(total - available), total: Double(total)).frame(maxWidth: 240)
                Text("\(bytes(Int64(total - available))) \(l10n.s.diskUsed) · \(bytes(Int64(available))) \(l10n.s.diskFree)").font(.caption)
            }
        }
    }

    private var fileTools: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(text[.choose]) { service.chooseFolders() }.disabled(service.busy || CleanupProbe.root != nil)
                Button(text[.scan]) { folder = nil; service.scan() }.disabled(service.roots.isEmpty || service.busy)
                if tool == 1 { Button(text[.duplicates]) { service.findDuplicates() }.disabled(service.result.files.isEmpty || service.busy) }
                Spacer()
                Text("\(text[.files]): \(service.result.files.count)").monospacedDigit()
            }
            ForEach(service.roots, id: \.path) { Text("\(text[.scope]): \($0.path)").font(.caption).textSelection(.enabled) }
            if tool == 0 {
                HStack {
                    Picker("", selection: $filter) {
                        Text(text[.all]).tag(0); Text(text[.large]).tag(1); Text(text[.old]).tag(2)
                    }.labelsHidden().frame(width: 180)
                    Stepper("\(megabytes) MB", value: $megabytes, in: 1...100_000, step: 10)
                    Stepper("\(text[.age]): \(days)", value: $days, in: 1...3650, step: 30)
                }.font(.caption)
            }
        }
    }

    private var storageResults: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 9) {
                if let folder {
                    Button { self.folder = service.roots.contains(folder) ? nil : folder.deletingLastPathComponent(); shown = 100 } label: {
                        Label(folder.path, systemImage: "arrow.up")
                    }.buttonStyle(.plain)
                }
                ForEach(childFolders.prefix(shown)) { value in
                    Button { folder = value.url; shown = 100 } label: {
                        HStack { Label(value.url.lastPathComponent, systemImage: "folder.fill"); Spacer(); Text(bytes(value.bytes)) }
                    }.buttonStyle(.plain).padding(9).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
                ForEach(filtered.prefix(shown)) { file in
                    StorageFileRow(file: file, onPreview: { if (try? StorageLocalAccess.validate(file)) != nil { preview = file.url } })
                    Divider()
                }
                if filtered.count > shown || childFolders.count > shown { Button(text[.more]) { shown += 100 } }
                issues
                StorageRecoveryView()
            }.padding(.vertical, 4)
        }
    }

    private var childFolders: [StorageFolderTotal] {
        service.result.folders.values.filter { value in
            if let folder { return value.url != folder && value.url.deletingLastPathComponent() == folder }
            return service.roots.contains(value.url)
        }.sorted { $0.bytes > $1.bytes }
    }

    private var filtered: [StorageFileSnapshot] {
        service.result.files.filter { file in
            let scope = folder == nil || file.url.deletingLastPathComponent() == folder
            let matches = filter == 0 || (filter == 1 && file.logicalBytes >= Int64(megabytes) * 1_000_000)
                || (filter == 2 && StorageInspectionPolicy.isOld(file, days: days))
            return scope && matches
        }.sorted { $0.logicalBytes > $1.logicalBytes }
    }

    private var issues: some View {
        DisclosureGroup("\(text[.skipped]): \(service.result.skipped) · \(text[.denied]): \(service.result.denied)") {
            ForEach(service.result.issues) { issue in
                Text("\(issue.path) — \(issue.reason == .excluded ? text[.skipped] : text[.denied])")
                    .font(.caption).textSelection(.enabled)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(!service.hasScanned ? text[.scope] : service.result.isPartial || service.duplicates.limited || service.duplicates.cancelled || !service.duplicates.issues.isEmpty ? text[.partial] : text[.complete])
                Spacer()
                Text("\(text[.selected]): \(service.selection.count) · \(text[.estimated]): \(bytes(service.selectedBytes))")
                Button(text[.review]) { review = true }.disabled(service.selection.isEmpty || service.busy)
            }.font(.callout)
            Text(text[.limits]).font(.caption2).foregroundStyle(.secondary)
            Text(text[.recovery]).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func save(_ value: Int, key: String) {
        guard CleanupProbe.root == nil else { return }
        UserDefaults.standard.set(value, forKey: key)
    }

    private func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }
}

struct StorageFileRow: View {
    let file: StorageFileSnapshot
    var onPreview: (() -> Void)?
    var allowsSelection = true
    @ObservedObject private var service = StorageInspectionService.shared
    private var text: StorageInspectionStrings { .current }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: Binding(get: { service.selection.contains(file.id) }, set: { service.select(file, included: $0) }))
                .labelsHidden().disabled(service.busy || !allowsSelection).accessibilityLabel(file.url.path)
            VStack(alignment: .leading, spacing: 4) {
                Text(file.url.lastPathComponent).font(.body.weight(.medium))
                Text("\(text[.kind]): \(file.url.pathExtension.isEmpty ? text[.unknown] : file.url.pathExtension)").font(.caption2).foregroundStyle(.secondary)
                Text(file.url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Text("\(text[.modified]): \(file.modified?.formatted(date: .abbreviated, time: .shortened) ?? text[.unknown])")
                    .font(.caption2).foregroundStyle(.secondary)
                HStack {
                    Text("\(text[.logical]): \(ByteCountFormatter.string(fromByteCount: file.logicalBytes, countStyle: .file))")
                    Text("\(text[.localSize]): \(ByteCountFormatter.string(fromByteCount: file.allocatedBytes, countStyle: .file))").foregroundStyle(.secondary)
                }.font(.caption)
            }
            Spacer(minLength: 0)
            if let onPreview { Button(action: onPreview) { Image(systemName: "eye") }.accessibilityLabel(text[.review]) }
            Button { NSWorkspace.shared.activateFileViewerSelecting([file.url]) } label: { Image(systemName: "arrow.up.forward.square") }
                .accessibilityLabel(text[.reveal])
        }.buttonStyle(.borderless).padding(.vertical, 5)
    }
}

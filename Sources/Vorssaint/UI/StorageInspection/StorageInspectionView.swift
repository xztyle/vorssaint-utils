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
    @State private var navigation = StorageMapNavigation()
    @State private var content = StorageMapContent()
    @State private var focusedItem: String?
    @State private var otherItemsOnly = false
    @State private var shown = 100
    @State private var review = false
    @State private var preview: URL?
    private var text: StorageInspectionStrings { .current }
    private var folder: URL? { navigation.current }
    private var mapText: StorageMapStrings { .init(language: l10n.language) }

    var body: some View {
        mainContent
        .padding(22).frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $review) { StorageTrashReviewView() }
        .quickLookPreview($preview)
        .onDisappear { service.cancel() }
        .onChange(of: service.roots) { _, _ in navigation.reset(); refreshContent() }
        .onChange(of: navigation) { _, _ in shown = 100; otherItemsOnly = false; focusedItem = nil; refreshContent() }
        .onChange(of: filter) { _, _ in shown = 100; otherItemsOnly = false; navigation.reset(); refreshContent() }
        .onChange(of: megabytes) { _, value in save(value, key: DefaultsKey.storageLargeMegabytes); refreshContent() }
        .onChange(of: days) { _, value in save(value, key: DefaultsKey.storageOldDays); refreshContent() }
        .onReceive(service.$result) { refreshContent(result: $0) }
        .onAppear {
            if UserDefaults.standard.object(forKey: DefaultsKey.storageLargeMegabytes) == nil { megabytes = 100 }
            if UserDefaults.standard.object(forKey: DefaultsKey.storageOldDays) == nil { days = 180 }
        }
    }

    private var mainContent: some View {
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
                Button(text[.scan]) { navigation.reset(); otherItemsOnly = false; service.scan() }.disabled(service.roots.isEmpty || service.busy)
                if tool == 1 { Button(text[.duplicates]) { service.findDuplicates() }.disabled(service.result.files.isEmpty || service.busy) }
                Spacer()
                Text("\(text[.files]): \(service.result.files.count)").monospacedDigit()
            }
            ForEach(service.roots, id: \.path) { root in
                Text("\(text[.scope]): \(root.lastPathComponent)")
                    .font(.caption).lineLimit(1).help(root.path)
            }
            if tool == 0 {
                HStack {
                    Picker("", selection: $filter) {
                        Text(text[.all]).tag(0); Text(text[.large]).tag(1); Text(text[.old]).tag(2)
                    }.labelsHidden().frame(width: 180)
                    if filter == 1 { Stepper("\(megabytes) MB", value: $megabytes, in: 1...100_000, step: 10) }
                    if filter == 2 { Stepper("\(text[.age]): \(days)", value: $days, in: 1...3650, step: 30) }
                }.font(.caption)
            }
        }
    }

    private var storageResults: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 9) {
                browsingBar
                if service.hasScanned, filter == 0, !otherItemsOnly {
                    mapAndList
                } else { fileList }
                issues
                StorageRecoveryView()
            }.padding(.vertical, 4)
        }
    }

    private var mapAndList: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                storageMap.frame(width: 340)
                ScrollView { fileList }.frame(minWidth: 300)
            }.frame(minWidth: 656).frame(height: 344)
            VStack(spacing: 12) {
                storageMap
                ScrollView { fileList }.frame(height: 344)
            }
        }
    }

    private var storageMap: some View {
        StorageMapView(items: content.bubbles, selected: service.selection, focused: $focusedItem,
            onOpen: openMapItem, onSelect: selectMapItem, onReveal: revealMapItem,
            onUp: { visit(navigation.parent(roots: service.roots)) }).disabled(service.busy)
    }

    private var fileList: some View {
        LazyVStack(alignment: .leading, spacing: 9) {
            ForEach(childFolders.prefix(shown)) { value in folderRow(value) }
            ForEach(filtered.prefix(shown)) { file in fileRow(file); Divider() }
            if filtered.count > shown || childFolders.count > shown { Button(text[.more]) { shown += 100 } }
        }
    }

    private func folderRow(_ value: StorageFolderTotal) -> some View {
        Button { visit(value.url) } label: {
            HStack { Label(value.url.lastPathComponent, systemImage: "folder.fill").lineLimit(1); Spacer(); Text(bytes(value.bytes)).monospacedDigit() }
        }.buttonStyle(.plain).padding(9).help(value.url.path)
            .background(focusedItem == value.id ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            .onHover { focusedItem = $0 ? value.id : (focusedItem == value.id ? nil : focusedItem) }
    }

    private func fileRow(_ file: StorageFileSnapshot) -> some View {
        StorageFileRow(file: file, onPreview: { if (try? StorageLocalAccess.validate(file)) != nil { preview = file.url } }, compact: filter == 0)
            .padding(.horizontal, 9)
            .background(focusedItem == file.id ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .onHover { focusedItem = $0 ? file.id : (focusedItem == file.id ? nil : focusedItem) }
    }

    private var childFolders: [StorageFolderTotal] {
        guard otherItemsOnly else { return content.folders }
        let heavy = heavyItemIDs
        return content.folders.filter { !heavy.contains($0.id) }
    }

    private var filtered: [StorageFileSnapshot] {
        guard otherItemsOnly else { return content.files }
        let heavy = heavyItemIDs
        return content.files.filter { !heavy.contains($0.id) }
    }

    private var heavyItemIDs: Set<String> { Set(content.bubbles.filter { $0.kind != .other }.map(\.id)) }

    private var browsingBar: some View {
        let labels = SettingsNavigationStrings.localized(l10n.language)
        return HStack(spacing: 10) {
            HStack(spacing: 14) {
                Button { if otherItemsOnly { otherItemsOnly = false } else { navigation.back() } } label: { Image(systemName: "chevron.left") }
                    .disabled(!navigation.canGoBack && !otherItemsOnly).help(labels.back).accessibilityLabel(labels.back)
                Button { navigation.forward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!navigation.canGoForward).help(labels.forward).accessibilityLabel(labels.forward)
            }.padding(9).background(HUDBackdrop(cornerRadius: 12))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    Button(mapText[.roots]) { visit(nil) }
                    ForEach(navigation.breadcrumbs(roots: service.roots), id: \.path) { crumb in
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        Button(crumb.lastPathComponent) { visit(crumb) }.help(crumb.path)
                    }
                    if otherItemsOnly { Image(systemName: "chevron.right"); Text(mapText[.other]) }
                }
            }
        }.buttonStyle(.plain).font(.caption).padding(.vertical, 4)
    }

    private func visit(_ url: URL?) { otherItemsOnly = false; navigation.visit(url) }

    private func refreshContent(result: StorageScanResult? = nil) {
        let result = result ?? service.result
        if let folder, result.folders[folder.path] == nil { navigation.reset() }
        if filter == 0, folder == nil, !navigation.canGoBack, service.roots.count == 1,
           let root = service.roots.first, result.folders[root.path] != nil { navigation.visit(root) }
        content = StorageMapContent.make(result: result, roots: service.roots, folder: folder,
            minimumBytes: filter == 1 ? Int64(megabytes) * 1_000_000 : nil,
            modifiedBefore: filter == 2 ? Date().addingTimeInterval(-Double(days) * 86_400) : nil)
    }

    private func openMapItem(_ item: StorageMapItem) {
        if item.kind == .folder { visit(item.url) }
        else if item.kind == .other { otherItemsOnly = true; shown = 100; focusedItem = nil }
        else if let file = content.files.first(where: { $0.id == item.id }), (try? StorageLocalAccess.validate(file)) != nil {
            preview = file.url
        }
    }

    private func selectMapItem(_ item: StorageMapItem, included: Bool) {
        guard let file = content.files.first(where: { $0.id == item.id }) else { return }
        service.select(file, included: included)
    }

    private func revealMapItem(_ item: StorageMapItem) {
        guard let url = item.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
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
                    .help(text[.limits])
                Spacer()
                Text("\(text[.selected]): \(service.selection.count) · \(text[.estimated]): \(bytes(service.selectedBytes))")
                Button(text[.review]) { review = true }.disabled(service.selection.isEmpty || service.busy)
            }.font(.callout)
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
    var compact = false
    @ObservedObject private var service = StorageInspectionService.shared
    private var text: StorageInspectionStrings { .current }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: Binding(get: { service.selection.contains(file.id) }, set: { service.select(file, included: $0) }))
                .labelsHidden().disabled(service.busy || !allowsSelection).accessibilityLabel(file.url.path)
            if compact { compactDetails } else { fullDetails }
            Spacer(minLength: 0)
            if let onPreview { Button(action: onPreview) { Image(systemName: "eye") }.accessibilityLabel(text[.review]) }
            Button { NSWorkspace.shared.activateFileViewerSelecting([file.url]) } label: { Image(systemName: "arrow.up.forward.square") }
                .accessibilityLabel(text[.reveal])
        }.buttonStyle(.borderless).padding(.vertical, 5)
    }

    private var compactDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(file.url.lastPathComponent).font(.body.weight(.medium)).lineLimit(1).truncationMode(.middle)
            Text("\(text[.localSize]): \(ByteCountFormatter.string(fromByteCount: file.allocatedBytes, countStyle: .file))")
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }.help(file.url.path).onTapGesture(count: 2) { onPreview?() }
    }

    private var fullDetails: some View {
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
    }
}

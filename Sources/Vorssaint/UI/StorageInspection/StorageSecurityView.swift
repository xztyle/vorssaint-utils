// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct StorageSecurityView: View {
    let malwareMode: Bool
    @ObservedObject private var service = StorageInspectionService.shared
    @State private var installConfirmation = false
    private var text: StorageInspectionStrings { .current }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if malwareMode { malwareControls; malwareResult }
                else { securityControls; securityRows }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmationDialog(text[.install], isPresented: $installConfirmation) {
            Button(text[.install]) { service.installEngine() }
        } message: { Text(text[.engineMissing]) }
    }

    private var malwareControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text[.localOnly])
            Text(service.engineVersion.isEmpty ? text[.engineMissing] : service.engineVersion).font(.callout)
            HStack {
                Button(text[.definitions]) { service.refreshEngine() }
                if !service.engineAvailable { Button(text[.install]) { installConfirmation = true }.disabled(CleanupProbe.root != nil) }
                Button(text[.update]) { service.updateDefinitions() }.disabled(!service.engineAvailable)
            }.disabled(service.busy)
            Text("\(text[.definitions]): \(service.definitionDate?.formatted(date: .abbreviated, time: .shortened) ?? text[.unknown])")
            Text(service.definitionsVerified ? text[.verified] : ClamAVSupport.fresh(service.definitionDate) ? text[.definitionFailure] : text[.stale]).foregroundStyle(.secondary)
            Divider()
            ForEach(service.roots, id: \.path) { Text("\(text[.scope]): \($0.path)").font(.caption).textSelection(.enabled) }
            HStack {
                Button(text[.choose]) { service.chooseFolders() }.disabled(CleanupProbe.root != nil)
                Button(text[.storage]) { service.scan() }.disabled(service.roots.isEmpty)
                Button(text[.malware]) { service.scanMalware() }
                    .disabled(service.result.files.isEmpty || !service.definitionsVerified || !ClamAVSupport.fresh(service.definitionDate))
            }.disabled(service.busy)
            Text("\(text[.files]): \(service.result.files.count)").font(.caption)
            Text(text[.limits]).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var malwareResult: some View {
        if let result = service.malware {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text(result.failed || result.cancelled ? text[.failed] : result.incomplete ? text[.partial] : text[.complete]).font(.headline)
                    if !result.findings.isEmpty { Text("\(text[.findings]): \(result.findings.count)") }
                    else if !result.failed && !result.cancelled { Text(text[.noMatches]) }
                    Text("\(text[.files]): \(result.scanned) · \(text[.skipped]): \(result.skipped)").font(.caption)
                    ForEach(result.findings) { finding in
                        Text("\(finding.path)\n\(finding.signature)").font(.callout).textSelection(.enabled)
                    }
                    DisclosureGroup(text[.review]) { Text(result.detail).font(.caption.monospaced()).textSelection(.enabled) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var securityControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text[.securityNote]).foregroundStyle(.secondary)
            Text(CleanupProbe.root.map { $0.appendingPathComponent("LaunchAgents").path } ?? text[.startupScope]).font(.caption)
            Text(text[.securityBounds]).font(.caption).foregroundStyle(.secondary)
            if service.securityPartial { Text(text[.partial]).foregroundStyle(.orange) }
            HStack {
                Button(text[.apps]) { service.inspectApplications() }.disabled(CleanupProbe.root != nil)
                Button(text[.startup]) { service.inspectStartup() }
            }.disabled(service.busy)
            HStack {
                Button(text[.updatesSettings]) { openSettings("com.apple.Software-Update-Settings.extension") }
                Button(text[.loginSettings]) { openSettings("com.apple.LoginItems-Settings.extension") }
            }.disabled(CleanupProbe.root != nil)
        }
    }

    private var securityRows: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            ForEach(service.securityRows) { row in
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(row.label).font(.headline)
                        Text(row.url.path).font(.caption).textSelection(.enabled)
                        if let executable = row.executable { Text(executable).font(.caption.monospaced()).textSelection(.enabled) }
                        Text(signature(row.signature))
                        if let team = row.teamID { Text(team).font(.caption.monospaced()) }
                        Text(row.gatekeeper == .accepted ? text[.accepted] : row.gatekeeper == .rejected ? text[.rejected] : text[.unknown])
                        if row.quarantined { Text(text[.quarantine]).font(.caption) }
                        if !row.detail.isEmpty { Text(row.detail).font(.caption).textSelection(.enabled) }
                        Button(text[.reveal]) { NSWorkspace.shared.activateFileViewerSelecting([row.url]) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.accessibilityElement(children: .contain)
            }
        }
    }

    private func signature(_ value: SecurityInspectionRow.Signature) -> String {
        switch value {
        case .valid: return text[.valid]
        case .invalid: return text[.invalid]
        case .unsigned: return text[.unsigned]
        case .unknown: return text[.unknown]
        }
    }

    private func openSettings(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:" + pane) else { return }
        NSWorkspace.shared.open(url)
    }
}

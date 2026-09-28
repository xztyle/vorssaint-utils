// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import UserNotifications

/// One Settings home for the installable Cleaner module. The system cleaner
/// and WhatsApp downloads keep separate controls and schedules, while sharing
/// the module's availability and permission portal entry.
struct CleanerSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var router = SettingsRouter.shared
    @AppStorage(DefaultsKey.whatsAppDownloadsEnabled) private var whatsAppEnabled = false
    @State private var tool = Tool.system

    private enum Tool: String {
        case system, inspection, whatsApp
    }

    /// A panel surface can ask for a specific tool; the hint is one-shot.
    private func consumeToolHint() {
        guard let hint = router.cleanerTool else { return }
        router.cleanerTool = nil
        guard let wanted = Tool(rawValue: hint), wanted != .whatsApp || whatsAppEnabled else { return }
        tool = wanted
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                Picker("", selection: $tool) {
                    Label(l10n.s.cleanerName, systemImage: "sparkles")
                        .tag(Tool.system)
                    Label(StorageInspectionStrings.current[.title], systemImage: "internaldrive").tag(Tool.inspection)
                    if whatsAppEnabled { Label(FeatureStrings.whatsAppDownloads(l10n.language).title,
                          systemImage: "arrow.down.doc")
                        .tag(Tool.whatsApp) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 440)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)

                Divider()
            }

            if tool == .inspection { StorageInspectionView() }
            else if whatsAppEnabled, tool == .whatsApp {
                WhatsAppDownloadsSettings()
            } else {
                CleanerView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            if !whatsAppEnabled { tool = .system }
            consumeToolHint()
        }
        .onChange(of: router.cleanerTool) { _, _ in consumeToolHint() }
        .onChange(of: whatsAppEnabled) { _, enabled in
            tool = enabled ? .whatsApp : .system
            WhatsAppDownloadScheduler.shared.syncWithPreferences()
            WhatsAppDownloadOrganizer.shared.syncWithPreferences()
            if !enabled {
                WhatsAppDownloadManager.shared.reset()
                WhatsAppDownloadOrganizer.shared.stop()
            }
        }
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import SwiftUI

struct EnergyAppsBreakdown: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var monitor = SystemMonitor.shared
    @AppStorage(DefaultsKey.monitorInterval) private var monitorInterval = 2
    @State private var expanded = false
    @State private var rows: [ProcessUsage] = []
    @State private var loading = false
    @State private var lastRefresh = Date.distantPast
    @State private var requestID = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: toggleExpanded) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text(l10n.s.energyAppsTitle)
                    Spacer()
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if expanded { expandedContent }
        }
        .font(.system(size: 10.5)).foregroundStyle(.secondary)
        .onReceive(monitor.$snapshot) { _ in refreshIfDue() }
        .onDisappear(perform: reset)
    }

    @ViewBuilder private var expandedContent: some View {
        if rows.isEmpty {
            Text(loading ? l10n.s.breakdownMeasuring : l10n.s.energyAppsIdle).foregroundStyle(.tertiary)
        } else {
            ForEach(rows) { row in
                ProcessUsageRow(row: row,
                    value: String(format: "%.1f%%", locale: MetricFormat.locale, row.value),
                    iconSize: 14, leadingPadding: 16)
            }
        }
        Text(FeatureStrings.powerFlow(l10n.language)[.activityNote])
            .font(.system(size: 9)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
    }

    private func toggleExpanded() {
        expanded.toggle()
        requestID = UUID()
        if expanded {
            rows = ProcessUsageService.shared.cachedTop(.energy, limit: 15) ?? []
            refresh()
        } else { rows = []; loading = false }
    }

    private func refreshIfDue() {
        guard expanded, !loading,
              Date().timeIntervalSince(lastRefresh) >= Double(Defaults.sanitizedMonitorInterval(monitorInterval)) else { return }
        refresh()
    }

    private func reset() {
        expanded = false
        requestID = UUID()
        rows = []
        loading = false
    }

    private func refresh() {
        lastRefresh = Date()
        loading = true
        let currentRequest = requestID
        let interval = Double(Defaults.sanitizedMonitorInterval(monitorInterval))
        DispatchQueue.global(qos: .utility).async {
            let result = ProcessUsageService.shared.top(.energy, limit: 15, sampleInterval: interval)
            DispatchQueue.main.async {
                guard expanded, requestID == currentRequest else { return }
                loading = false
                rows = result
            }
        }
    }
}

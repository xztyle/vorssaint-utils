// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import SwiftUI

/// iStat-style sensors list: hottest reading per sensor group, with a heat bar.
struct SensorsCard: View {
    @ObservedObject private var l10n = L10n.shared
    @StateObject private var sampler = SensorGroupsSampler()
    @AppStorage(DefaultsKey.temperatureUnit) private var temperatureUnit = TemperatureUnit.celsius.rawValue

    private var text: MonitorDetailStrings { .localized(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text.sensors).font(.system(size: 11)).foregroundStyle(.secondary)
            if sampler.readings.isEmpty {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity)
            }
            ForEach(SensorGroup.allCases.filter { sampler.readings[$0] != nil }) { group in
                row(group, celsius: sampler.readings[group]!)
            }
        }
        .panelCard()
        .onAppear { sampler.start() }
        .onDisappear { sampler.stop() }
    }

    private func row(_ group: SensorGroup, celsius: Double) -> some View {
        let name = text.sensorGroups[SensorGroup.allCases.firstIndex(of: group)!]
        return HStack(spacing: 8) {
            Text(name).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 8)
            heatBar(celsius).frame(width: 44, height: 4)
            Text(MetricFormat.temperature(celsius, unit: TemperatureUnit(rawValue: temperatureUnit) ?? .celsius))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .frame(minWidth: 44, alignment: .trailing)
        }
    }

    /// 30 °C empty to 100 °C full; green, then orange, then red.
    private func heatBar(_ celsius: Double) -> some View {
        let fraction = min(1, max(0, (celsius - 30) / 70))
        let color: Color = celsius >= 85 ? .red : celsius >= 70 ? .orange : .green
        return GeometryReader { proxy in
            Capsule().fill(Color.primary.opacity(0.08))
                .overlay(alignment: .leading) { Capsule().fill(color).frame(width: proxy.size.width * fraction) }
        }
    }
}

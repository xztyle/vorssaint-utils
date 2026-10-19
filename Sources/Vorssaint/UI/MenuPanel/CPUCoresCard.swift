// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import SwiftUI

/// iStat-style CPU breakdown: user/system split, one bar per core, load average.
struct CPUCoresCard: View {
    @ObservedObject private var l10n = L10n.shared
    @StateObject private var sampler = CPUCoreSampler()

    private var text: MonitorDetailStrings { .localized(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let reading = sampler.reading {
                split(reading)
                cores(reading)
                load(reading)
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity)
            }
        }
        .panelCard()
        .onAppear { sampler.start() }
        .onDisappear { sampler.stop() }
    }

    private func split(_ reading: CPUCoreReading) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 12) {
                legend(text.user, value: reading.user, color: .blue)
                legend(text.system, value: reading.system, color: .red)
            }
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    Rectangle().fill(Color.blue).frame(width: proxy.size.width * reading.user)
                    Rectangle().fill(Color.red).frame(width: proxy.size.width * reading.system)
                    Spacer(minLength: 0)
                }
                .background(Color.primary.opacity(0.08))
                .clipShape(Capsule())
            }
            .frame(height: 6)
        }
    }

    private func legend(_ title: String, value: Double, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value.formatted(.percent.precision(.fractionLength(0))))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
        }
    }

    private func cores(_ reading: CPUCoreReading) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(text.cores).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: text.coreKindsFormat, reading.performanceCount,
                            reading.cores.count - reading.performanceCount))
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(reading.cores.indices, id: \.self) { index in
                    coreBar(reading.cores[index])
                }
            }
            .frame(height: 34)
        }
    }

    private func coreBar(_ core: CPUCoreReading.Core) -> some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Rectangle().fill(Color.red).frame(height: proxy.size.height * core.system)
                Rectangle().fill(Color.blue).frame(height: proxy.size.height * core.user)
            }
            .frame(maxWidth: .infinity)
            .background(Color.primary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }

    private func load(_ reading: CPUCoreReading) -> some View {
        HStack {
            Text(text.loadAverage).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Text(reading.load.map { String(format: "%.2f", locale: .current, $0) }.joined(separator: "  "))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
        }
    }
}

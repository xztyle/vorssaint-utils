// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import SwiftUI

/// iStat-style ring chart: proportional arcs with a legend beside it.
struct MonitorRing: View {
    struct Segment: Identifiable {
        let title: String
        let value: Double
        let color: Color
        let label: String
        var id: String { title }
    }

    let segments: [Segment]
    var center: String = ""

    private var total: Double { max(segments.map(\.value).reduce(0, +), 1) }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.08), lineWidth: 9)
                ForEach(arcs, id: \.segment.id) { arc in
                    Circle()
                        .trim(from: arc.start, to: arc.end)
                        .stroke(arc.segment.color, style: StrokeStyle(lineWidth: 9, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
                Text(center).font(.system(size: 12, weight: .semibold).monospacedDigit())
            }
            .frame(width: 66, height: 66)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(segments) { segment in
                    HStack(spacing: 6) {
                        Circle().fill(segment.color).frame(width: 7, height: 7)
                        Text(segment.title).font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text(segment.label).font(.system(size: 11, weight: .semibold).monospacedDigit())
                    }
                }
            }
        }
    }

    private var arcs: [(segment: Segment, start: Double, end: Double)] {
        var start = 0.0
        return segments.map { segment in
            let end = start + segment.value / total
            defer { start = end }
            return (segment, start, end)
        }
    }
}

/// Memory as Activity Monitor counts it: used = apps + wired + compressed.
struct MemoryRingCard: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var monitor = SystemMonitor.shared

    private var text: MonitorDetailStrings { .localized(l10n.language) }

    var body: some View {
        let snapshot = monitor.snapshot
        if let total = snapshot.memoryTotal, total > 0, let used = snapshot.memoryUsed {
            let app = snapshot.memoryAppUsed ?? 0, compressed = snapshot.memoryCompressed ?? 0
            let cached = snapshot.memoryCached ?? 0
            let wired = used > app + compressed ? used - app - compressed : 0
            let free = total > used + cached ? total - used - cached : 0
            MonitorRing(segments: [
                .init(title: text.app, value: Double(app), color: .blue, label: bytes(app)),
                .init(title: text.wired, value: Double(wired), color: .orange, label: bytes(wired)),
                .init(title: text.compressed, value: Double(compressed), color: .purple, label: bytes(compressed)),
                .init(title: text.cached, value: Double(cached), color: .gray, label: bytes(cached)),
                .init(title: text.free, value: Double(free), color: .primary.opacity(0.18), label: bytes(free)),
            ], center: (Double(used) / Double(total)).formatted(.percent.precision(.fractionLength(0))))
            .panelCard()
        }
    }

    private func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }
}

/// Main drive as a ring (used, purgeable, free), other drives as usage bars.
struct DiskRingCard: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var monitor = SystemMonitor.shared

    private var text: MonitorDetailStrings { .localized(l10n.language) }

    var body: some View {
        let devices = Self.volumes(monitor.snapshot.disk)
        if let main = devices.first(where: \.isInternal) ?? devices.first {
            VStack(alignment: .leading, spacing: 10) {
                let purgeable = min(main.purgeableBytes ?? 0, main.freeBytes)
                MonitorRing(segments: [
                    .init(title: text.used, value: Double(main.usedBytes), color: .blue,
                          label: MetricFormat.diskBytes(main.usedBytes)),
                    .init(title: l10n.s.diskPurgeable, value: Double(purgeable), color: .teal,
                          label: MetricFormat.diskBytes(purgeable)),
                    .init(title: text.free, value: Double(main.freeBytes - purgeable), color: .primary.opacity(0.18),
                          label: MetricFormat.diskBytes(main.freeBytes - purgeable)),
                ], center: MetricFormat.percent(main.usedFraction))
                ForEach(devices.filter { $0.id != main.id }, id: \.id) { volume($0) }
            }
            .panelCard()
        }
    }

    private func volume(_ device: DiskDeviceReading) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(device.name).font(.system(size: 11)).lineLimit(1)
                Spacer()
                Text(MetricFormat.diskBytes(device.freeBytes)).font(.system(size: 11, weight: .semibold).monospacedDigit())
            }
            GeometryReader { proxy in
                Capsule().fill(Color.primary.opacity(0.08))
                    .overlay(alignment: .leading) {
                        Capsule().fill(Color.blue).frame(width: proxy.size.width * device.usedFraction)
                    }
            }
            .frame(height: 4)
        }
    }

    /// One row per volume; APFS siblings on one container repeat the same space.
    private static func volumes(_ reading: DiskReading?) -> [DiskDeviceReading] {
        var seen = Set<String>()
        return (reading?.devices ?? []).filter { seen.insert($0.volumeUUID ?? $0.id).inserted }
    }
}

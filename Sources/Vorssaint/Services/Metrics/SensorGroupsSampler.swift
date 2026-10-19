// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import Foundation

/// iStat-style sensor list. Apple silicon SMC temperature keys are grouped by
/// prefix (Tp performance cores, Te efficiency cores, Tg GPU, …); each group
/// shows its hottest plausible reading. Read only while the menu is open.
enum SensorGroup: String, CaseIterable, Identifiable {
    case performanceCores, efficiencyCores, gpu, memory, battery, storage, wireless, enclosure, ambient
    var id: String { rawValue }

    /// SMC key prefix for each group.
    var prefix: String {
        switch self {
        case .performanceCores: "Tp"
        case .efficiencyCores: "Te"
        case .gpu: "Tg"
        case .memory: "Tm"
        case .battery: "TB"
        case .storage: "TH"
        case .wireless: "TW"
        case .enclosure: "Ts"
        case .ambient: "TA"
        }
    }

    static func group(for key: String) -> SensorGroup? {
        allCases.first { key.hasPrefix($0.prefix) }
    }
}

@MainActor
final class SensorGroupsSampler: ObservableObject {
    @Published private(set) var readings: [SensorGroup: Double] = [:]
    private var keys: [SensorGroup: [SMCClient.Key]]?
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func sample() {
        Task.detached(priority: .utility) { [keys] in
            guard let smc = SMCClient() else { return }
            let groups = keys ?? Dictionary(grouping: smc.keys { $0.hasPrefix("T") }) { SensorGroup.group(for: $0.name) }
                .reduce(into: [SensorGroup: [SMCClient.Key]]()) { result, entry in
                    if let group = entry.key { result[group] = entry.value }
                }
            let values = groups.compactMapValues { list in
                list.compactMap(smc.readValue).filter(Self.isPlausible).max()
            }
            await MainActor.run { [weak self] in
                self?.keys = groups
                self?.readings = values
            }
        }
    }

    nonisolated static func isPlausible(_ celsius: Double) -> Bool { celsius > 5 && celsius < 130 }
}

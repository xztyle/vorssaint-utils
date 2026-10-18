// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import Foundation

enum ChipPowerComponent: String, CaseIterable, Identifiable {
    case cpu, gpu, neuralEngine, memory
    var id: String { rawValue }
}

struct ChipPowerReading: Equatable {
    var watts: [ChipPowerComponent: Double] = [:]

    /// DRAM is shown separately, rather than counted again inside the chip.
    var chipWatts: Double? {
        let components: [ChipPowerComponent] = [.cpu, .gpu, .neuralEngine]
        guard components.allSatisfy({ watts[$0] != nil }) else { return nil }
        return components.compactMap { watts[$0] }.reduce(0, +)
    }
}

struct ChipEnergyCounter: Equatable {
    let name: String
    let unit: String
    let value: Int64

    var component: ChipPowerComponent? {
        let suffix = name.replacingOccurrences(of: "^DIE_[0-9]+_", with: "", options: .regularExpression)
        switch suffix {
        case "CPU Energy": return .cpu
        case "GPU Energy": return .gpu
        case "ANE", "ANE Energy": return .neuralEngine
        case "DRAM", "DRAM Energy": return .memory
        default: return nil
        }
    }

    var joulesPerUnit: Double? {
        switch unit {
        case "J": return 1
        case "mJ": return 1e-3
        case "uJ", "µJ", "μJ": return 1e-6
        case "nJ": return 1e-9
        default: return nil
        }
    }
}

/// Counter differences use monotonic time and each channel's reported unit.
/// A missing channel, reset or long sampling gap primes a new baseline.
struct ChipPowerDelta {
    private var previous: [ChipEnergyCounter] = []
    private var previousTime: TimeInterval?

    mutating func sample(_ counters: [ChipEnergyCounter], at uptime: TimeInterval) -> ChipPowerReading {
        defer { previous = counters; previousTime = uptime }
        guard let previousTime else { return ChipPowerReading() }
        let elapsed = uptime - previousTime
        guard elapsed.isFinite, elapsed >= 0.1, elapsed <= 30 else { return ChipPowerReading() }
        var result = ChipPowerReading()
        for component in ChipPowerComponent.allCases {
            let current = aggregates(counters, component: component)
            let old = aggregates(previous, component: component)
            result.watts[component] = power(current, previous: old, elapsed: elapsed)
        }
        return result
    }

    private func aggregates(_ counters: [ChipEnergyCounter], component: ChipPowerComponent) -> [ChipEnergyCounter] {
        let matching = counters.filter { $0.component == component }
        let dies = matching.filter { $0.name.hasPrefix("DIE_") }
        return (dies.isEmpty ? matching : dies).sorted { $0.name < $1.name }
    }

    private func power(_ current: [ChipEnergyCounter], previous: [ChipEnergyCounter], elapsed: Double) -> Double? {
        guard !current.isEmpty, current.count == previous.count else { return nil }
        var joules = 0.0
        for (counter, old) in zip(current, previous) {
            guard counter.name == old.name, counter.unit == old.unit, counter.value >= 0,
                  old.value >= 0, counter.value >= old.value, let unit = counter.joulesPerUnit else { return nil }
            joules += Double(counter.value - old.value) * unit
        }
        let watts = joules / elapsed
        return watts.isFinite && watts >= 0 && watts < 1000 ? watts : nil
    }
}

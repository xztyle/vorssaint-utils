// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import Darwin
import Foundation

/// Per-core CPU load for the CPU menu, sampled only while that menu is open.
/// Usage is the busy share of ticks between two host_processor_info reads.
struct CPUCoreReading: Equatable {
    struct Core: Equatable { let user: Double; let system: Double; var total: Double { user + system } }
    let cores: [Core]
    /// Performance-core count (perf level 0); the rest are efficiency cores.
    /// Core order is not mapped to levels, so bars are not labelled by kind.
    let performanceCount: Int
    let load: [Double]

    var user: Double { cores.isEmpty ? 0 : cores.map(\.user).reduce(0, +) / Double(cores.count) }
    var system: Double { cores.isEmpty ? 0 : cores.map(\.system).reduce(0, +) / Double(cores.count) }
}

@MainActor
final class CPUCoreSampler: ObservableObject {
    @Published private(set) var reading: CPUCoreReading?
    private var previous: [[UInt32]] = []
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil; previous = [] }

    private func sample() {
        guard let ticks = Self.ticks() else { return }
        defer { previous = ticks }
        guard previous.count == ticks.count else { return }
        let cores = zip(ticks, previous).map { now, before -> CPUCoreReading.Core in
            Self.core(now: now, before: before)
        }
        var load = [Double](repeating: 0, count: 3)
        getloadavg(&load, 3)
        reading = CPUCoreReading(cores: cores, performanceCount: Self.performanceCores(total: cores.count), load: load)
    }

    /// user, system, idle, nice ticks per logical CPU.
    static func ticks() -> [[UInt32]]? {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        let states = Int(CPU_STATE_MAX)
        return (0..<Int(count)).map { cpu in
            (0..<states).map { UInt32(bitPattern: info[cpu * states + $0]) }
        }
    }

    static func core(now: [UInt32], before: [UInt32]) -> CPUCoreReading.Core {
        let delta = { (state: Int32) in Double(now[Int(state)] &- before[Int(state)]) }
        let user = delta(CPU_STATE_USER) + delta(CPU_STATE_NICE), system = delta(CPU_STATE_SYSTEM)
        let total = user + system + delta(CPU_STATE_IDLE)
        guard total > 0 else { return .init(user: 0, system: 0) }
        return .init(user: user / total, system: system / total)
    }

    /// hw.perflevel0 is the performance cluster on Apple silicon.
    static func performanceCores(total: Int) -> Int {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("hw.perflevel0.logicalcpu", &value, &size, nil, 0) == 0, value > 0 else { return total }
        return min(total, Int(value))
    }
}

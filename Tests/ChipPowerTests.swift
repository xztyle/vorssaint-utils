// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import Foundation

enum ChipPowerTests {
    static func run(_ suite: TestSuite) {
        units(suite)
        recovery(suite)
        aggregateSelection(suite)
        breakdown(suite)
    }

    private static func counters(_ cpu: Int64, gpu: Int64 = 2_000_000_000) -> [ChipEnergyCounter] {
        [.init(name: "CPU Energy", unit: "mJ", value: cpu),
         .init(name: "GPU Energy", unit: "nJ", value: gpu),
         .init(name: "ANE", unit: "uJ", value: 0),
         .init(name: "DRAM", unit: "mJ", value: cpu / 2)]
    }

    private static func units(_ suite: TestSuite) {
        var delta = ChipPowerDelta()
        suite.expect(delta.sample(counters(1000), at: 1).watts.isEmpty, "first energy sample is unknown, not zero")
        let reading = delta.sample(counters(5000, gpu: 4_000_000_000), at: 3)
        suite.expectClose(reading.watts[.cpu] ?? -1, 2, "millijoules divide by actual elapsed seconds")
        suite.expectClose(reading.watts[.gpu] ?? -1, 1, "nanojoules do not become millijoules")
        suite.expect(reading.watts[.neuralEngine] == 0, "an unchanged available counter is valid zero power")
        suite.expectClose(reading.chipWatts ?? -1, 3, "chip total includes CPU GPU and neural engine once")
        suite.expectClose(reading.watts[.memory] ?? -1, 1, "memory remains a separate measurement")
        suite.expect(ChipPowerReading(watts: [.cpu: 2, .gpu: 1]).chipWatts == nil,
            "missing neural engine does not create a partial chip total")
        suite.expect(ChipEnergyCounter(name: "CPU Energy", unit: "unknown", value: 10).joulesPerUnit == nil,
            "unknown units are not guessed")
    }

    private static func recovery(_ suite: TestSuite) {
        var delta = ChipPowerDelta()
        _ = delta.sample(counters(5000), at: 1)
        suite.expect(delta.sample(counters(1000), at: 3).watts[.cpu] == nil, "reset energy counter is not negative watts")
        suite.expect(delta.sample(counters(5000), at: 5).watts[.cpu] == 2, "counter reset recovers on next real interval")
        suite.expect(delta.sample(counters(9000), at: 50).watts.isEmpty, "wake or long gap establishes a fresh baseline")
        suite.expect(delta.sample(counters(13000), at: 52).watts[.cpu] == 2, "readings recover after a long gap")
        suite.expect(delta.sample([], at: 54).watts.isEmpty, "sample failure never reuses old watts")
        suite.expect(delta.sample(counters(17000), at: 56).watts.isEmpty, "missing sample requires a baseline")
        suite.expect(delta.sample(counters(21000), at: 58).watts[.cpu] == 2, "missing sample recovers")
        suite.expect(delta.sample(counters(25000), at: 57).watts.isEmpty, "backward time cannot claim current power")
    }

    private static func aggregateSelection(_ suite: TestSuite) {
        let names = ["CPU Energy", "DIE_0_CPU Energy", "DIE_1_CPU Energy", "DIE_0_EACC_CPU0"]
        var delta = ChipPowerDelta()
        _ = delta.sample(names.map { .init(name: $0, unit: "mJ", value: 1000) }, at: 1)
        let reading = delta.sample(names.map { .init(name: $0, unit: "mJ", value: 3000) }, at: 3)
        suite.expectClose(reading.watts[.cpu] ?? -1, 2, "sum die aggregates without double-counting total or per-core channels")
        let missingDie = delta.sample([.init(name: "DIE_0_CPU Energy", unit: "mJ", value: 5000)], at: 5)
        suite.expect(missingDie.watts[.cpu] == nil, "a disappearing die does not report a partial total")
        let changedUnit = delta.sample([.init(name: "DIE_0_CPU Energy", unit: "nJ", value: 7000)], at: 7)
        suite.expect(changedUnit.watts[.cpu] == nil, "unit changes prime a fresh baseline")
    }

    private static func breakdown(_ suite: TestSuite) {
        let model = PowerFlowModel.make(adapter: 60, battery: 40, system: 18,
                                        connected: true, sampledAt: Date(), chip: 8)
        suite.expect(model.breakdown == [.init(role: .chip, watts: 8), .init(role: .other, watts: 12)],
            "Mac branch separates measured chip and calculated other use")
        suite.expectClose(model.breakdownLinks.compactMap(\.watts).reduce(0, +), 20, "secondary branches conserve Mac input")
        let mismatch = PowerFlowModel.make(adapter: 60, battery: 40, system: 18,
                                           connected: true, sampledAt: Date(), chip: 25)
        suite.expect(mismatch.readingsSettling && mismatch.breakdown.last?.watts == nil,
            "independent chip interval exceeding current Mac input is settling, not negative other power")
        suite.expect(mismatch.breakdownLinks.allSatisfy { $0.watts == nil }, "inconsistent secondary flow is not fabricated")
        let missing = PowerFlowModel.make(adapter: 60, battery: 40, system: 18,
                                          connected: true, sampledAt: Date())
        suite.expect(missing.breakdown.isEmpty, "unsupported chip counters preserve the original power diagram")
    }
}

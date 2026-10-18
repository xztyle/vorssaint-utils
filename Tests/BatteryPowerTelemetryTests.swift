// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import Foundation

enum BatteryPowerTelemetryTests {
    static func run(_ suite: TestSuite) {
        for milliwatts: Int32 in [0, 1, -1, 101249, -26348, 999999, -999999] {
            suite.expectClose(decode(milliwatts) ?? .nan, Double(milliwatts) / 1000,
                              "live SMC power preserves signed milliwatts: \(milliwatts)")
        }
        suite.expect(decode(0, fallback: 103) == 0, "a fresh zero reading replaces a stale charging value")
        for invalid: Int32 in [1000000, -1000000, .max, .min] {
            suite.expect(decode(invalid, fallback: -12) == -12, "out-of-range power falls back without inventing watts")
        }
        for bytes: [UInt8]? in [nil, [], [1], [1, 0, 0], [1, 0, 0, 0, 0]] {
            suite.expect(BatteryPowerTelemetry.watts(bytes: bytes, type: "si32", fallback: 22) == 22,
                         "missing, short or extended sensor data retains the registry fallback")
        }
        for type: String? in [nil, "ui32", "flt ", "si16"] {
            suite.expect(BatteryPowerTelemetry.watts(bytes: [129, 139, 1, 0], type: type, fallback: 22) == 22,
                         "unrecognized sensor encoding never treats bytes as signed power")
        }
        for fallback: Double? in [nil, .nan, .infinity, -.infinity, 1000, -1000] {
            suite.expect(BatteryPowerTelemetry.watts(bytes: nil, type: nil, fallback: fallback) == nil,
                         "unavailable or invalid fallback remains unknown")
        }
        liveFlow(suite)
    }

    private static func decode(_ milliwatts: Int32, fallback: Double? = 22) -> Double? {
        let bits = UInt32(bitPattern: milliwatts)
        let bytes = (0..<4).map { UInt8(truncatingIfNeeded: bits >> ($0 * 8)) }
        return BatteryPowerTelemetry.watts(bytes: bytes, type: "si32", fallback: fallback)
    }

    private static func liveFlow(_ suite: TestSuite) {
        // First direct-power probe on the owner's Mac; registry current was lagging.
        let battery = BatteryPowerTelemetry.watts(bytes: [129, 139, 1, 0], type: "si32", fallback: 107.67)
        let flow = PowerFlowModel.make(adapter: 132.89483642578125, battery: battery, system: 19.679046630859375,
                                      connected: true, sampledAt: Date())
        suite.expectClose(flow.destinations.first?.watts ?? .nan, 31.64583642578125,
                          "the diagram uses current battery power rather than the lagging registry current")
        suite.expect(!flow.readingsSettling && flow.state == .charging, "valid direct power produces a charging split")
        let paused = PowerFlowModel.make(adapter: 20, battery: decode(0, fallback: 103), system: 16,
                                        connected: true, sampledAt: Date())
        suite.expect(paused.state == .paused && paused.links.count == 1 && !paused.readingsSettling,
                     "a fresh hold removes the old charge branch immediately")
    }
}

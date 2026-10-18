// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import Foundation

/// macOS 27 removed Temperature from AppleSmartBattery. These battery-cell
/// sensors remain readable; CPU and enclosure temperatures are never substitutes.
final class BatteryTemperatureSampler {
    private let smc: SMCClient?
    private var keys: [SMCClient.Key] = []
    private var resolved = false

    init(smc: SMCClient?) { self.smc = smc }

    func sample() -> Double? {
        guard let smc else { return nil }
        if !resolved {
            resolved = true
            keys = ["TB0T", "TB1T"].compactMap { smc.key(named: $0) }
        }
        return Self.validated(keys.compactMap { smc.readValue($0) })
    }

    static func validated(_ readings: [Double]) -> Double? {
        readings.filter { $0.isFinite && (0...65).contains($0) }.max()
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import Foundation

/// Read-only signed battery flow. Missing SMC data retains the registry fallback.
final class BatteryPowerSampler {
    private let smc: SMCClient?
    private var key: SMCClient.Key?
    private var resolved = false

    init(smc: SMCClient?) { self.smc = smc }

    func sample(fallback: Double? = nil) -> Double? {
        if !resolved {
            resolved = true
            key = smc?.key(named: "B0AP")
        }
        let bytes = key.flatMap { smc?.readBytes($0) }
        return BatteryPowerTelemetry.watts(bytes: bytes, type: key?.dataType, fallback: fallback)
    }
}

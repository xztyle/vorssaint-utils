// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import Foundation

/// Apple-silicon B0AP reports signed milliwatts in little-endian si32 bytes.
/// Shared by the live monitor and the protected charge-control service.
/// This battery key is not the generic big-endian SMC integer format.
enum BatteryPowerTelemetry {
    static func watts(bytes: [UInt8]?, type: String?, fallback: Double?) -> Double? {
        if type == "si32", let bytes, bytes.count == 4 {
            let bits = bytes.enumerated().reduce(UInt32(0)) { value, byte in
                value | UInt32(byte.element) << UInt32(byte.offset * 8)
            }
            let watts = Double(Int32(bitPattern: bits)) / 1000
            if abs(watts) < 1000 { return watts }
        }
        return fallback.flatMap { $0.isFinite && abs($0) < 1000 ? $0 : nil }
    }
}

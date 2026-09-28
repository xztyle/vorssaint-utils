// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import Foundation
import IOKit

/// The control service and power panel share the same battery-property decoder.
enum BatterySensor {
    static func sample() -> BatterySample? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let dictionary = properties?.takeRetainedValue() as? [String: Any] else { return nil }
        return decode(dictionary, at: Date())
    }

    static func decode(_ props: [String: Any], at date: Date) -> BatterySample {
        let capacity = number(props["CurrentCapacity"])
        let maximum = number(props["MaxCapacity"])
        var percent: Int?
        if let capacity, let maximum, maximum > 0, capacity >= 0, capacity <= maximum {
            percent = Int((capacity / maximum * 100).rounded())
        }
        let temperature = number(props["Temperature"]).map { $0 / 10 - 273.15 }
        let volts = number(props["Voltage"]).map { $0 / 1000 }
        let current = signedAmperage(props["Amperage"] ?? props["InstantAmperage"])
        let watts = volts.flatMap { v in current.map { v * $0 / 1000 } }
        return BatterySample(at: date, percent: percent, temperature: temperature,
                             connected: adapterPresent(props),
                             charging: props["IsCharging"] as? Bool, watts: watts,
                             externalPowerConnected: props["ExternalConnected"] as? Bool)
    }

    private static func adapterPresent(_ props: [String: Any]) -> Bool? {
        // CHIE cuts effective AC without unplugging the adapter. A physical
        // disconnect must still win over a lagging effective-power reading.
        if let raw = props["AppleRawExternalConnected"] { return raw as? Bool }
        return props["ExternalConnected"] as? Bool
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }

    private static func signedAmperage(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber else { return nil }
        // IORegistry can expose a negative 32-bit SMC current as unsigned.
        let raw = number.int64Value
        let signed = raw > Int64(Int32.max) && raw <= Int64(UInt32.max)
            ? Int64(Int32(bitPattern: UInt32(raw))) : raw
        return (-30000...30000).contains(signed) ? Double(signed) : nil
    }
}

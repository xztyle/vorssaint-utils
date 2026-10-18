// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import Foundation
import IOKit

/// The control service and power panel share the same battery-property decoder.
enum BatterySensor {
    private static let power = BatteryPowerSampler(smc: SMCClient())
    private static let temperature = BatteryTemperatureSampler(smc: SMCClient())

    static func sample() -> BatterySample? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let dictionary = properties?.takeRetainedValue() as? [String: Any] else { return nil }
        var sample = decode(dictionary, at: Date(), liveWatts: power.sample())
        if sample.temperature == nil { sample.temperature = temperature.sample() }
        return sample
    }

    static func decode(_ props: [String: Any], at date: Date, liveWatts: Double? = nil) -> BatterySample {
        let live = BatteryPowerTelemetry.watts(bytes: nil, type: nil, fallback: liveWatts)
        let percent = chargePercent(props, current: "CurrentCapacity", maximum: "MaxCapacity")
            .map { Int($0.rounded()) }
        let rawPercent = chargePercent(props, current: "AppleRawCurrentCapacity", maximum: "AppleRawMaxCapacity")
        let temperature = number(props["Temperature"]).map { $0 / 10 - 273.15 }
        // Registry current and charging flags can lag for a minute after a pause.
        // The existing hold test tolerates flow up to 0.8 W as a noise floor.
        let charging = live.map { $0 > 0.8 } ?? (props["IsCharging"] as? Bool)
        let watts = live ?? registryWatts(props)
        return BatterySample(at: date, percent: percent, temperature: temperature,
                             connected: adapterPresent(props),
                             charging: charging, watts: watts,
                             fullyCharged: props["FullyCharged"] as? Bool,
                             externalPowerConnected: props["ExternalConnected"] as? Bool,
                             rawPercent: rawPercent)
    }

    private static func chargePercent(_ props: [String: Any], current: String, maximum: String) -> Double? {
        guard let capacity = number(props[current]), let maximum = number(props[maximum]),
              maximum > 0, capacity >= 0, capacity <= maximum else { return nil }
        return capacity / maximum * 100
    }

    private static func registryWatts(_ props: [String: Any]) -> Double? {
        let volts = number(props["Voltage"]).map { $0 / 1000 }
        let current = signedAmperage(props["Amperage"] ?? props["InstantAmperage"])
        return volts.flatMap { v in current.map { v * $0 / 1000 } }
    }

    private static func adapterPresent(_ props: [String: Any]) -> Bool? {
        // CHIE can clear both connection flags while the adapter stays plugged in.
        // AdapterDetails tracks physical presence on Macs with this behavior.
        if let details = props["AdapterDetails"] as? [String: Any] {
            return hasAdapterIdentity(details)
        }
        if let details = props["AppleRawAdapterDetails"] as? [[String: Any]] {
            return details.contains(where: hasAdapterIdentity)
        }
        if let raw = props["AppleRawExternalConnected"] { return raw as? Bool }
        return props["ExternalConnected"] as? Bool
    }

    private static func hasAdapterIdentity(_ details: [String: Any]) -> Bool {
        // An unplugged Mac can retain only FamilyCode=0. It is not an adapter.
        return (number(details["Watts"]) ?? 0) > 0
            || (number(details["FamilyCode"]) ?? 0) > 0
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

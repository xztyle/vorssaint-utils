// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import IOKit
import IOKit.ps

/// One power reading. Every field is optional: a Mac mini has no battery, a
/// desktop may expose no SMC power key, so the UI shows only what is real.
struct PowerReading {
    var sampledAt = Date()
    var batteryTemperature: Double?
    var systemWatts: Double?       // total the Mac is consuming (SMC PSTR)
    var adapterWatts: Double?      // real-time draw from the adapter (SMC PDTR)
    var adapterMaxWatts: Double?   // the charger's rated wattage
    var batteryWatts: Double?      // + charging, - discharging
    var chargePercent: Int?        // current charge level
    var timeRemainingSeconds: TimeInterval? // system estimate while discharging
    var healthPercent: Double?     // max capacity vs design (battery health)
    var cycleCount: Int?
    var isCharging = false
    var externalConnected = false
    var hasBattery = false
    var components: [PowerComponentReading] = []
    var chip = ChipPowerReading()

    var isEmpty: Bool {
        systemWatts == nil && adapterWatts == nil && adapterMaxWatts == nil
            && batteryWatts == nil && !hasBattery
    }
}

/// Reads power without any special permission. Total system power and adapter
/// input and live battery flow come from the SMC. AppleSmartBattery supplies
/// the rating and a battery-flow fallback. Chip counters measure interval energy.
/// Anything the hardware does not expose stays nil.
final class PowerSampler {
    /// Internal-battery presence is immutable for the lifetime of a Mac boot.
    /// Resolve it once so desktops do not keep probing a service they cannot have.
    static let hasInternalBattery: Bool = {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return false }
        IOObjectRelease(service)
        return true
    }()

    private let smc: SMCClient?
    private let batteryPower: BatteryPowerSampler
    private let batteryTemperature: BatteryTemperatureSampler
    private let chip = ChipPowerSampler()
    private var systemKey: SMCClient.Key?
    private var adapterKey: SMCClient.Key?
    private var resolvedKeys = false
    private var componentKeys: [PowerComponent: SMCClient.Key] = [:]
    private var batteryService: io_service_t = 0

    /// `PSTR` = System Total Power. `PDTR` = DC-In (adapter) Total Power.
    /// They stay separate because adapter input can include connected devices.
    private static let systemPowerKey = "PSTR"
    private static let adapterPowerKey = "PDTR"

    init(smc: SMCClient?) {
        self.smc = smc
        batteryPower = BatteryPowerSampler(smc: smc)
        batteryTemperature = BatteryTemperatureSampler(smc: smc)
    }

    deinit {
        if batteryService != 0 {
            IOObjectRelease(batteryService)
        }
    }

    func sample() -> PowerReading {
        var reading = PowerReading()
        reading.chip = chip.sample()
        samplePowerSensors(into: &reading)
        if let props = batteryProperties() {
            sampleBattery(props, into: &reading)
        }
        reading.systemWatts = MetricFormat.systemPowerWatts(
            measured: reading.systemWatts,
            batteryWatts: reading.batteryWatts,
            externalConnected: reading.externalConnected)
        return reading
    }

    private func samplePowerSensors(into reading: inout PowerReading) {
        guard let smc else { return }
        if !resolvedKeys {
            resolvedKeys = true
            systemKey = smc.key(named: Self.systemPowerKey)
            adapterKey = smc.key(named: Self.adapterPowerKey)
            for component in PowerComponent.allCases {
                componentKeys[component] = component.keys.lazy.compactMap { smc.key(named: $0) }.first
            }
        }
        reading.systemWatts = plausibleWatts(systemKey)
        reading.adapterWatts = plausibleWatts(adapterKey)
        reading.components = sampleComponents(smc)
    }

    private func sampleBattery(_ props: [String: Any], into reading: inout PowerReading) {
        let battery = BatterySensor.decode(props, at: reading.sampledAt, liveWatts: batteryPower.sample())
        reading.batteryTemperature = battery.temperature ?? batteryTemperature.sample()
        reading.hasBattery = true
        reading.externalConnected = (props["ExternalConnected"] as? Bool) ?? false
        reading.isCharging = battery.charging ?? false
        reading.timeRemainingSeconds = BatteryTimeSupport.remainingSeconds(
            timeToEmptyMinutes: timeToEmptyMinutes(),
            externalConnected: reading.externalConnected,
            isCharging: reading.isCharging)
        reading.batteryWatts = battery.watts
        if let adapter = props["AdapterDetails"] as? [String: Any],
           let rated = adapter["Watts"] as? Int, rated > 0 {
            reading.adapterMaxWatts = Double(rated)
        }
        if let capacity = props["CurrentCapacity"] as? Int,
           let maxCapacity = props["MaxCapacity"] as? Int, maxCapacity > 0 {
            reading.chargePercent = Int((Double(capacity) / Double(maxCapacity) * 100).rounded())
        }
        reading.cycleCount = props["CycleCount"] as? Int
        reading.healthPercent = batteryHealth(props)
    }

    private func batteryHealth(_ props: [String: Any]) -> Double? {
        // The cached system value matches macOS's Maximum Capacity display.
        MaxCapacityProbe.shared.refreshIfStale()
        if let exact = MaxCapacityProbe.shared.percent { return Double(exact) }
        guard let design = batteryInt("DesignCapacity", in: props), design > 0 else { return nil }
        let fullCharge = batteryInt("NominalChargeCapacity", in: props)
            ?? batteryInt("FullChargeCapacity", in: props)
            ?? batteryInt("AppleRawMaxCapacity", in: props)
        guard let fullCharge, fullCharge > 0 else { return nil }
        return min(100, Double(fullCharge) / Double(design) * 100)
    }

    private func plausibleWatts(_ key: SMCClient.Key?) -> Double? {
        guard let key, let smc, let watts = smc.readValue(key), watts > 0, watts < 1000 else { return nil }
        return watts
    }

    private func sampleComponents(_ smc: SMCClient) -> [PowerComponentReading] {
        PowerComponent.allCases.compactMap { component in
            guard let key = componentKeys[component], let value = smc.readValue(key),
                  value.isFinite, value >= 0, value < 1000 else { return nil }
            return PowerComponentReading(component: component, watts: value)
        }
    }

    private func batteryProperties() -> [String: Any]? {
        let service = resolvedBatteryService()
        guard service != 0 else { return nil }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let dict = properties?.takeRetainedValue() as? [String: Any]
        else {
            IOObjectRelease(service)
            batteryService = 0
            return nil
        }
        return dict
    }

    /// Uses the same public power-source field as the established battery
    /// monitor users are likely to compare against. A negative value means the
    /// system is still calculating, so the UI keeps that state instead of
    /// substituting a more volatile private estimate.
    private func timeToEmptyMinutes() -> Int? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue()
        else { return nil }
        let sources = list as [CFTypeRef]
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
                    as? [String: Any],
                  description[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue,
                  let minutes = intValue(description[kIOPSTimeToEmptyKey]) else { continue }
            return minutes
        }
        return nil
    }

    private func batteryInt(_ key: String, in props: [String: Any]) -> Int? {
        if let value = intValue(props[key]) {
            return value
        }
        if let batteryData = props["BatteryData"] as? [String: Any] {
            return intValue(batteryData[key])
        }
        return nil
    }

    private func intValue(_ value: Any?) -> Int? {
        switch value {
        case let value as Int:
            return value
        case let value as NSNumber:
            let int64 = value.int64Value
            guard int64 >= Int64(Int.min), int64 <= Int64(Int.max) else { return nil }
            return Int(int64)
        case let value as String:
            return Int(value)
        default:
            return nil
        }
    }

    private func resolvedBatteryService() -> io_service_t {
        guard Self.hasInternalBattery else { return 0 }
        if batteryService != 0 { return batteryService }
        batteryService = IOServiceGetMatchingService(kIOMainPortDefault,
                                                     IOServiceMatching("AppleSmartBattery"))
        return batteryService
    }
}

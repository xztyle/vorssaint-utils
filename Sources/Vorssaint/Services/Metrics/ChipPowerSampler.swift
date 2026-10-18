// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import Foundation
import Darwin

/// Read-only Energy Model counters. Resolve this private system interface at
/// runtime so unsupported macOS versions keep the existing power sensors.
final class ChipPowerSampler {
    private let api: EnergyReportAPI?
    private var delta = ChipPowerDelta()

    init() { api = EnergyReportAPI() }

    func sample() -> ChipPowerReading {
        delta.sample(api?.counters() ?? [], at: ProcessInfo.processInfo.systemUptime)
    }
}

private final class EnergyReportAPI {
    typealias CopyChannels = @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFDictionary>?
    typealias Subscribe = @convention(c) (UnsafeMutableRawPointer?, CFMutableDictionary?,
        UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>?, UInt64, CFTypeRef?) -> UnsafeMutableRawPointer?
    typealias Samples = @convention(c) (UnsafeMutableRawPointer?, CFMutableDictionary?, CFTypeRef?) -> Unmanaged<CFDictionary>?
    typealias Label = @convention(c) (CFDictionary?) -> Unmanaged<CFString>?
    typealias Value = @convention(c) (CFDictionary?, Int32) -> Int64

    private static let handle = dlopen("/usr/lib/libIOReport.dylib", RTLD_LAZY | RTLD_LOCAL)
    private let subscription: UnsafeMutableRawPointer
    private let channels: CFMutableDictionary
    private let samples: Samples
    private let name: Label
    private let unit: Label
    private let value: Value

    init?() {
        guard let copy: CopyChannels = Self.symbol("IOReportCopyChannelsInGroup"),
              let subscribe: Subscribe = Self.symbol("IOReportCreateSubscription"),
              let samples: Samples = Self.symbol("IOReportCreateSamples"),
              let name: Label = Self.symbol("IOReportChannelGetChannelName"),
              let unit: Label = Self.symbol("IOReportChannelGetUnitLabel"),
              let value: Value = Self.symbol("IOReportSimpleGetIntegerValue"),
              let desired = copy("Energy Model" as CFString, nil, 0, 0, 0)?.takeRetainedValue(),
              let mutable = CFDictionaryCreateMutableCopy(nil, 0, desired) else { return nil }
        var subscribed: Unmanaged<CFMutableDictionary>?
        guard let subscription = subscribe(nil, mutable, &subscribed, 0, nil) else {
            subscribed?.release()
            return nil
        }
        self.subscription = subscription
        channels = subscribed?.takeRetainedValue() ?? mutable
        self.samples = samples; self.name = name; self.unit = unit; self.value = value
    }

    deinit { Unmanaged<AnyObject>.fromOpaque(subscription).release() }

    func counters() -> [ChipEnergyCounter] {
        guard let snapshot = samples(subscription, channels, nil)?.takeRetainedValue(),
              let items = (snapshot as NSDictionary)["IOReportChannels"] as? [NSDictionary] else { return [] }
        return items.compactMap { item in
            let channel = item as CFDictionary
            guard let name = name(channel)?.takeUnretainedValue() as String?,
                  let unit = unit(channel)?.takeUnretainedValue() as String? else { return nil }
            let counter = ChipEnergyCounter(name: name, unit: unit, value: value(channel, 0))
            return counter.component == nil ? nil : counter
        }
    }

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle, let address = dlsym(handle, name) else { return nil }
        return unsafeBitCast(address, to: T.self)
    }
}

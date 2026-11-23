// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import Foundation
import Darwin
import IOKit.pwr_mgt

struct BatteryNativePolicySnapshot {
    let boot: String?
    let data: Data?
}

protocol BatteryNativePolicyTransport {
    func bootIdentifier() throws -> String
    func snapshot() throws -> BatteryNativePolicySnapshot
    func registration() throws -> BatteryNativeRegistration
    func write(_ data: Data, boot: String, basedOn: BatteryNativePolicySnapshot) throws
    func reload() throws
}

/// Uses only powerd's charging-policy domain. Never writes PowerUI's manual
/// charge-limit domain or changes the limit displayed in System Settings.
final class BatteryNativePolicyIO: BatteryNativePolicyTransport {
    private let domain = "com.apple.powerd.charging" as CFString

    private func requireRoot() throws {
        guard geteuid() == 0, ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27 else {
            throw BatteryHardwareError.unavailable
        }
    }

    func bootIdentifier() throws -> String {
        try requireRoot()
        var buffer = [CChar](repeating: 0, count: 128), size = 128
        guard sysctlbyname("kern.bootsessionuuid", &buffer, &size, nil, 0) == 0, size < buffer.count,
              let value = String(validatingCString: buffer), UUID(uuidString: value) != nil else { throw BatteryHardwareError.shape }
        return value
    }

    func snapshot() throws -> BatteryNativePolicySnapshot {
        try requireRoot()
        guard CFPreferencesSynchronize(domain, kCFPreferencesAnyUser, kCFPreferencesCurrentHost),
              let values = CFPreferencesCopyMultiple(nil, domain, kCFPreferencesAnyUser, kCFPreferencesCurrentHost) as? [String: Any],
              values["bootSessionUUID"] == nil || values["bootSessionUUID"] is String,
              values["policies"] == nil || values["policies"] is Data else { throw BatteryHardwareError.shape }
        return .init(boot: values["bootSessionUUID"] as? String, data: values["policies"] as? Data)
    }

    func registration() throws -> BatteryNativeRegistration {
        try requireRoot()
        let result = BoundedProcessRunner.run("/usr/bin/pmset", ["-g", "battlimit"], timeout: 2, maxOutputBytes: 65_536,
            environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "C", "LC_ALL": "C"])
        guard result.status == 0, !result.timedOut, let text = String(data: result.output, encoding: .utf8) else {
            throw BatteryHardwareError.unavailable
        }
        return try BatteryNativeRegistration(output: text)
    }

    func write(_ data: Data, boot: String, basedOn before: BatteryNativePolicySnapshot) throws {
        try requireRoot()
        _ = try BatteryNativePolicyArchive(data: data)
        let current = try snapshot()
        guard current.boot == before.boot, current.data == before.data else { throw BatteryHardwareError.conflict }
        let changes: [String: Any] = ["bootSessionUUID": boot, "policies": data]
        CFPreferencesSetMultiple(changes as CFDictionary, nil, domain, kCFPreferencesAnyUser, kCFPreferencesCurrentHost)
        guard CFPreferencesSynchronize(domain, kCFPreferencesAnyUser, kCFPreferencesCurrentHost) else { throw BatteryHardwareError.mismatch }
        let after = try snapshot()
        guard after.boot == boot, after.data == data else { throw BatteryHardwareError.mismatch }
    }

    func reload() throws {
        try requireRoot()
        let previous = try powerdPID()
        guard kill(previous, SIGHUP) == 0 else { throw BatteryHardwareError.unavailable }
        let deadline = Date().addingTimeInterval(6)
        repeat {
            usleep(100_000)
            if let fresh = try? powerdPID(), fresh != previous {
                Self.sleepIfLidClosed()
                return
            }
        } while Date() < deadline
        throw BatteryHardwareError.mismatch
    }

    /// A restarted powerd no longer acts on a lid that was already shut, so a
    /// Mac in a bag would stay awake until its battery is empty. Request the
    /// sleep the lid asked for when the kernel says a closed lid means sleep
    /// (false with an external display or closed-lid mode). The fresh powerd
    /// can refuse briefly while it starts, so a refusal is retried.
    static func sleepIfLidClosed(attempts: Int = 10) {
        for attempt in 1...attempts {
            guard lidRequiresSleep() else { return }
            let port = IOPMFindPowerManagement(kIOMainPortDefault)
            guard port != 0 else { return }
            let result = IOPMSleepSystem(port)
            IOServiceClose(port)
            if result == kIOReturnSuccess || attempt == attempts { return }
            usleep(500_000)
        }
    }

    /// True when the lid is shut and the kernel says that means sleep.
    static func lidRequiresSleep() -> Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        func flag(_ key: String) -> Bool {
            IORegistryEntryCreateCFProperty(root, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Bool == true
        }
        return flag(kAppleClamshellStateKey) && flag(kAppleClamshellCausesSleepKey)
    }

    private func powerdPID() throws -> pid_t {
        var pids = [pid_t](repeating: 0, count: 8192)
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard bytes > 0, bytes < pids.count * MemoryLayout<pid_t>.size else { throw BatteryHardwareError.unavailable }
        let candidates = pids.prefix(Int(bytes) / MemoryLayout<pid_t>.size).filter { pid in
            // The SDK cannot import PROC_PIDPATHINFO_MAXSIZE's expression.
            var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            return pid > 1 && proc_pidpath(pid, &path, UInt32(path.count)) > 0
                && String(cString: path) == "/System/Library/CoreServices/powerd.bundle/powerd"
        }
        guard candidates.count == 1 else { throw BatteryHardwareError.conflict }
        return candidates[0]
    }
}

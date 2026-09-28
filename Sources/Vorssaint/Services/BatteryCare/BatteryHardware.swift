// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import Foundation
import IOKit

protocol BatteryKeyTransport {
    func inspectKey(named: String) throws -> SMCClient.Key
    func checkedRead(_ key: SMCClient.Key) throws -> [UInt8]
    func writeBytes(_ bytes: [UInt8], to: SMCClient.Key) throws
}
extension SMCClient: BatteryKeyTransport {}

enum BatteryHardwareError: Error { case unavailable, shape, mismatch, conflict }

/// Only these two documented-by-observation shapes are eligible on this backend.
/// Eligibility is not power-flow qualification; that runs explicitly in the daemon.
final class BatteryHardware {
    private let transport: BatteryKeyTransport
    private let charging: SMCClient.Key
    private let adapter: SMCClient.Key
    private(set) var expected: BatteryCommand?

    init(transport: BatteryKeyTransport) throws {
        self.transport = transport
        charging = try transport.inspectKey(named: "CHTE")
        adapter = try transport.inspectKey(named: "CHIE")
        guard charging.dataType == "ui32", charging.dataSize == 4,
              adapter.dataType == "hex_", adapter.dataSize == 1 else { throw BatteryHardwareError.shape }
        _ = try transport.checkedRead(charging)
        _ = try transport.checkedRead(adapter)
    }

    convenience init() throws {
        guard let smc = SMCClient() else { throw BatteryHardwareError.unavailable }
        try self.init(transport: smc)
    }

    func readState() throws -> BatteryCommand {
        let charge = try transport.checkedRead(charging)
        let ac = try transport.checkedRead(adapter)
        guard [Self.chargeBytes(false), Self.chargeBytes(true)].contains(charge),
              ac == [0] || ac == [8], !(ac == [8] && charge == Self.chargeBytes(true)) else {
            throw BatteryHardwareError.conflict
        }
        if ac == [8] { return .discharge }
        return charge == Self.chargeBytes(true) ? .hold : .charge
    }

    func verifyOwnership() throws {
        guard let expected else { return }
        let actual = try readState()
        guard actual == (expected == .system ? .charge : expected) else {
            throw BatteryHardwareError.conflict
        }
    }

    func apply(_ command: BatteryCommand) throws {
        // Never cut AC and inhibit charging together. Restore AC before charge
        // changes, and clear inhibit before adapter cut. Verify every step.
        if command == .discharge {
            try write(Self.chargeBytes(false), key: charging)
            try write([8], key: adapter)
        } else {
            try write([0], key: adapter)
            try write(Self.chargeBytes(command == .hold), key: charging)
        }
        expected = command
        try verifyOwnership()
    }

    private func write(_ bytes: [UInt8], key: SMCClient.Key) throws {
        if try transport.checkedRead(key) != bytes { try transport.writeBytes(bytes, to: key) }
        guard try transport.checkedRead(key) == bytes else { throw BatteryHardwareError.mismatch }
    }

    static func chargeBytes(_ inhibit: Bool) -> [UInt8] { [inhibit ? 1 : 0, 0, 0, 0] }

    static var fingerprint: String {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return ProcessInfo.processInfo.operatingSystemVersionString }
        defer { IOObjectRelease(service) }
        func property(_ key: String) -> String {
            guard let data = IORegistryEntryCreateCFProperty(service, key as CFString,
                kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data else { return "unknown" }
            return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .controlCharacters)
        }
        return [property("model"), property("firmware-version"),
                ProcessInfo.processInfo.operatingSystemVersionString].joined(separator: " · ")
    }
}

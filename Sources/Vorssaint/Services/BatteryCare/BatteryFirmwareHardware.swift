// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import Foundation

/// macOS 27 firmware charge limiter. The SMC itself stops charging at the
/// ceiling and resumes below the floor, so the limit holds through sleep,
/// helper restarts and app quits. Forced discharge still uses CHIE.
/// Key sizes, write order and values follow observed AlDente Pro 1.39.4.
final class BatteryFirmwareHardware: BatteryChargeHardware {
    static let backend = "firmware-limit"
    private static let active: UInt8 = 2

    private let transport: BatteryKeyTransport
    private let mode: SMCClient.Key      // bfF0: 0 off, 2 limit active
    private let ceiling: SMCClient.Key   // bfD0: stop charging at this percent
    private let floor: SMCClient.Key     // bfE0: resume charging below this percent
    private let adapter: SMCClient.Key   // CHIE: 8 disconnects adapter power
    private var upper = 80
    private(set) var expected: BatteryCommand?
    var backendName: String { Self.backend }

    init(transport: BatteryKeyTransport) throws {
        self.transport = transport
        mode = try transport.inspectKey(named: "bfF0")
        ceiling = try transport.inspectKey(named: "bfD0")
        floor = try transport.inspectKey(named: "bfE0")
        adapter = try transport.inspectKey(named: "CHIE")
        guard mode.dataSize == 1, ceiling.dataSize == 4, floor.dataSize == 4,
              adapter.dataType == "hex_", adapter.dataSize == 1 else { throw BatteryHardwareError.shape }
        for key in [mode, ceiling, floor, adapter] { _ = try transport.checkedRead(key) }
    }

    convenience init() throws {
        guard let smc = SMCClient() else { throw BatteryHardwareError.unavailable }
        try self.init(transport: smc)
    }

    func prepare(upper: Int, target: Int) { self.upper = min(100, max(1, upper)) }

    func readState() throws -> BatteryCommand {
        let on = try transport.checkedRead(mode), ac = try transport.checkedRead(adapter)
        guard on == [0] || on == [Self.active], ac == [0] || ac == [8] else { throw BatteryHardwareError.conflict }
        let limit = Int(try transport.checkedRead(ceiling).first ?? 0)
        guard ac == [0] || (on == [Self.active] && limit == 1) else { throw BatteryHardwareError.conflict }
        if ac == [8] { return .discharge }
        return on == [Self.active] && limit == 1 ? .hold : .charge
    }

    func verifyOwnership() throws {
        guard let expected else { return }
        guard try matches(expected) else { throw BatteryHardwareError.conflict }
    }

    func needsApply(_ command: BatteryCommand) -> Bool { (try? matches(command)) != true }

    func apply(_ command: BatteryCommand) throws {
        // Inhibit charging before cutting AC; reconnect AC before raising the limit.
        if command == .discharge {
            try writeLimit(1)
            try write([8], key: adapter)
        } else {
            try write([0], key: adapter)
            if let limit = limit(for: command) { try writeLimit(limit) } else { try write([0], key: mode) }
        }
        expected = command
        try verifyOwnership()
    }

    /// Nil turns the firmware limiter off and returns charging to macOS.
    private func limit(for command: BatteryCommand) -> Int? {
        switch command {
        case .system: return nil
        case .charge: return upper == 100 ? nil : upper
        case .hold, .discharge: return 1
        }
    }

    private func matches(_ command: BatteryCommand) throws -> Bool {
        guard try transport.checkedRead(adapter) == [command == .discharge ? 8 : 0] else { return false }
        guard let limit = limit(for: command) else { return try transport.checkedRead(mode) == [0] }
        return try transport.checkedRead(mode) == [Self.active]
            && transport.checkedRead(ceiling) == Self.percentBytes(limit)
            && transport.checkedRead(floor) == Self.percentBytes(limit - 1)
    }

    /// The firmware must see the limiter off while both thresholds change.
    private func writeLimit(_ limit: Int) throws {
        let high = Self.percentBytes(limit), low = Self.percentBytes(limit - 1)
        let on = try transport.checkedRead(mode) == [Self.active]
        if on, try transport.checkedRead(ceiling) == high, try transport.checkedRead(floor) == low { return }
        try write([0], key: mode)
        try write(high, key: ceiling)
        try write(low, key: floor)
        try write([Self.active], key: mode)
    }

    private func write(_ bytes: [UInt8], key: SMCClient.Key) throws {
        if try transport.checkedRead(key) != bytes { try transport.writeBytes(bytes, to: key) }
        guard try transport.checkedRead(key) == bytes else { throw BatteryHardwareError.mismatch }
    }

    /// The percentage sits in the first byte, as with the legacy CHTE flag.
    static func percentBytes(_ percent: Int) -> [UInt8] { [UInt8(min(100, max(0, percent))), 0, 0, 0] }
}

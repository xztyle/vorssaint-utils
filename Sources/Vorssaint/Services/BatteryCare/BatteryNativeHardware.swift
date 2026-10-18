// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import Foundation

/// Resident-helper lease, independent of the user's System Settings limit.
/// Registration alone is not qualification. The controller still measures flow.
final class BatteryNativeHardware: BatteryChargeHardware {
    private let io: BatteryNativePolicyTransport
    private let load: () -> BatteryNativeLease?
    private let save: (BatteryNativeLease?) throws -> Void
    private let owner: Int
    private let now: () -> Date
    private var upper = 80
    private var target = 80
    private var hold = 75
    private(set) var expected: BatteryCommand?
    var backendName: String { "native-owned-policy" }

    init(io: BatteryNativePolicyTransport, owner: Int,
         load: @escaping () -> BatteryNativeLease?, save: @escaping (BatteryNativeLease?) throws -> Void,
         now: @escaping () -> Date = Date.init) throws {
        self.io = io; self.owner = owner; self.load = load; self.save = save; self.now = now
        guard (2...Int(Int32.max)).contains(owner) else { throw BatteryHardwareError.unavailable }
        _ = try archive(snapshot: io.snapshot(), boot: io.bootIdentifier(), live: io.registration())
    }

    func prepare(upper: Int, target: Int, hold: Int) {
        self.upper = min(100, max(1, upper)); self.target = min(99, max(1, target))
        self.hold = min(self.upper - 1, max(1, hold))
    }

    func apply(_ command: BatteryCommand) throws {
        if let plan = plan(command) { try ensure(target: plan.target, drain: plan.drain) }
        else { try remove() }
        expected = command
        try verifyOwnership()
    }

    func readState() throws -> BatteryCommand {
        let live = try io.registration()
        guard !live.hasOtherOwner else { throw BatteryHardwareError.conflict }
        guard let lease = load() else { return .charge }
        guard live.confirms(lease, owner: owner) else { throw BatteryHardwareError.conflict }
        return lease.drain ? .discharge : lease.target < upper ? .hold : .charge
    }

    func verifyOwnership() throws {
        guard let expected else { return }
        if let lease = load(), let plan = plan(expected) {
            let live = try io.registration()
            guard !live.hasOtherOwner else { throw BatteryHardwareError.conflict }
            if !live.confirms(lease, owner: owner) { try ensure(target: plan.target, drain: plan.drain) }
        }
        let actual = try readState()
        guard actual == (expected == .system ? .charge : expected) else { throw BatteryHardwareError.conflict }
    }

    func needsApply(_ command: BatteryCommand) -> Bool {
        guard let plan = plan(command) else { return load() != nil }
        guard let lease = load() else { return true }
        return lease.owner != owner || lease.target != plan.target || lease.drain != plan.drain || lease.removalPending
    }

    private func plan(_ command: BatteryCommand) -> (target: Int, drain: Bool)? {
        guard command != .system, command != .charge || upper != 100 else { return nil }
        return (command == .hold ? hold : command == .discharge ? target : upper, command == .discharge)
    }

    private func archive(snapshot: BatteryNativePolicySnapshot, boot: String,
                         live: BatteryNativeRegistration) throws -> BatteryNativePolicyArchive {
        guard !live.hasOtherOwner else { throw BatteryHardwareError.conflict }
        if snapshot.boot == boot {
            guard let data = snapshot.data else { throw BatteryHardwareError.shape }
            let document = try BatteryNativePolicyArchive(data: data)
            guard document.records.allSatisfy({ $0.reason == BatteryNativePolicyArchive.reason || $0.terminated }) else {
                throw BatteryHardwareError.conflict
            }
            return document
        }
        guard live.rows.isEmpty, try io.registration().rows.isEmpty else { throw BatteryHardwareError.conflict }
        return try BatteryNativePolicyArchive(data: BatteryNativePolicyArchive.empty())
    }

    private func ensure(target: Int, drain: Bool) throws {
        let boot = try io.bootIdentifier(), live = try io.registration()
        guard !live.hasOtherOwner else { throw BatteryHardwareError.conflict }
        let previous = load()
        if let previous, previous.boot == boot, previous.owner == owner, previous.target == target,
           previous.drain == drain, !previous.removalPending, live.confirms(previous, owner: owner) { return }
        let before = try io.snapshot(), document = try archive(snapshot: before, boot: boot, live: live)
        var lease = previous?.boot == boot ? previous! : BatteryNativeLease(token: BatteryNativeLease.token(),
            boot: boot, owner: owner, target: target, drain: drain)
        guard document.records.allSatisfy({ $0.reason != BatteryNativePolicyArchive.reason || $0.token == lease.token }) else {
            throw BatteryHardwareError.conflict
        }
        let data = try document.replacing(token: lease.token, previousOwner: previous?.boot == boot ? previous?.owner : nil,
                                           owner: owner, target: target, drain: drain)
        try prepareAttempt(&lease, target: target, drain: drain)
        try save(lease) // Durable token and owner BEFORE any system write.
        try io.write(data, boot: boot, basedOn: before)
        try io.reload()
        guard try io.registration().confirms(lease, owner: owner) else { throw BatteryHardwareError.mismatch }
    }

    private func prepareAttempt(_ lease: inout BatteryNativeLease, target: Int, drain: Bool) throws {
        let time = now()
        if lease.target != target || lease.drain != drain || lease.removalPending { lease.attempts = [] }
        try recordAttempt(&lease, allowImmediate: lease.owner != owner, at: time)
        lease.owner = owner; lease.target = target; lease.drain = drain; lease.removalPending = false
    }

    private func recordAttempt(_ lease: inout BatteryNativeLease, allowImmediate: Bool, at time: Date) throws {
        lease.attempts = lease.attempts.filter { time.timeIntervalSince($0) < 600 }
        guard lease.attempts.count < 3, allowImmediate || lease.attempts.last.map({ time.timeIntervalSince($0) >= 60 }) != false else {
            throw BatteryHardwareError.unavailable
        }
        lease.attempts.append(time)
    }

    private func remove() throws {
        guard var lease = load() else { return }
        let boot = try io.bootIdentifier(), before = try io.snapshot(), live = try io.registration()
        guard lease.boot == boot, before.boot == boot else {
            guard !live.containsOwner(lease.owner) else { throw BatteryHardwareError.conflict }
            try save(nil); return
        }
        guard let bytes = before.data else { throw BatteryHardwareError.shape }
        let document = try BatteryNativePolicyArchive(data: bytes)
        let data = try document.removing(token: lease.token, previousOwner: lease.owner)
        if data != bytes || live.containsOwner(lease.owner) || lease.removalPending {
            if !lease.removalPending { lease.attempts = [] }
            try recordAttempt(&lease, allowImmediate: false, at: now())
            lease.removalPending = true; try save(lease)
            if data != bytes { try io.write(data, boot: boot, basedOn: before) }
            try io.reload()
            guard try !io.registration().containsOwner(lease.owner) else { throw BatteryHardwareError.mismatch }
        }
        try save(nil)
    }
}

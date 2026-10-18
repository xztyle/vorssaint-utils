// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import Foundation

extension BatteryController {
    func resumeNativeLeaseAtStart() -> Bool {
        guard hardware?.backendName == "native-owned-policy", state.nativeLease != nil,
              state.policy.enabled, !state.scheduledPause, state.operation == nil, !state.recoveryPending,
              state.qualifiedFingerprint == snapshot.fingerprint,
              state.chargeQualified || state.dischargeQualified else { return false }
        state.ownsHardware = true
        return true
    }

    /// Backends whose limit stays in force without this process re-applying it.
    var keepsLimitBetweenSteps: Bool {
        [BatteryFirmwareHardware.backend, "native-owned-policy"].contains(hardware?.backendName ?? "")
    }

    func defaultHardware() throws -> any BatteryChargeHardware {
        if let firmware = try? BatteryFirmwareHardware() {
            retireNativeLease()
            return firmware
        }
        if state.nativeLease == nil, let legacy = try? BatteryHardware() { return legacy }
        return try nativeHardware()
    }

    private func nativeHardware() throws -> BatteryNativeHardware {
        try BatteryNativeHardware(io: BatteryNativePolicyIO(), owner: Int(ProcessInfo.processInfo.processIdentifier),
            load: { [weak self] in self?.state.nativeLease }, save: { [weak self] lease in
                guard let self else { throw BatteryHardwareError.unavailable }
                state.nativeLease = lease
                guard self.save() else { throw BatteryJournal.Failure.write }
            })
    }

    /// A powerd rule left by the older backend would fight the firmware limit.
    private func retireNativeLease() {
        guard state.nativeLease != nil else { return }
        do { try nativeHardware().apply(.system) }
        catch { state.record(.recovery, at: Date(), detail: "native lease retirement: \(error)") }
    }

    /// The firmware limit outlives this process. Leave the saved ceiling in
    /// force on exit, so charging cannot pass it while the helper is away.
    func keepFirmwareCeiling() -> Bool {
        guard hardware?.backendName == BatteryFirmwareHardware.backend, state.policy.enabled,
              state.chargeQualified, !state.recoveryPending else { return false }
        hardware?.prepare(upper: state.policy.upper, target: state.policy.upper)
        do { try hardware?.apply(.charge) } catch { return false }
        snapshot.command = .charge
        state.ownsHardware = true
        return save()
    }

    func prepareHardware() {
        let fullCharge = state.operation?.kind == .topUp || state.operation?.kind == .calibration
            && state.operation?.phase != .discharge
        let target = state.operation?.kind == .discharge || state.operation?.phase == .discharge
            ? state.operation?.target ?? state.policy.upper : state.policy.upper
        hardware?.prepare(upper: fullCharge ? 100 : state.policy.upper, target: target)
    }
}

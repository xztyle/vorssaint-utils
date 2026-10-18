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

    func defaultHardware() throws -> any BatteryChargeHardware {
        if state.nativeLease == nil, let legacy = try? BatteryHardware() { return legacy }
        return try BatteryNativeHardware(io: BatteryNativePolicyIO(), owner: Int(ProcessInfo.processInfo.processIdentifier),
            load: { [weak self] in self?.state.nativeLease }, save: { [weak self] lease in
                guard let self else { throw BatteryHardwareError.unavailable }
                state.nativeLease = lease
                guard self.save() else { throw BatteryJournal.Failure.write }
            })
    }

    func prepareHardware() {
        let fullCharge = state.operation?.kind == .topUp || state.operation?.kind == .calibration
            && state.operation?.phase != .discharge
        let target = state.operation?.kind == .discharge || state.operation?.phase == .discharge
            ? state.operation?.target ?? state.policy.upper : state.policy.upper
        hardware?.prepare(upper: fullCharge ? 100 : state.policy.upper, target: target, hold: holdCeiling)
    }

    /// powerd ignores a 1% ceiling, so pause at the lower bound, or below the
    /// current charge when it is already lower (heat or sleep holds).
    var holdCeiling: Int { min(state.policy.lower, snapshot.sample?.percent ?? state.policy.lower) }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import Foundation

struct BatteryQualification {
    var stage = 0
    var began = Date()
    var matches = 0
    var lastSample: Date?
    var chargeDeferred = false
}

extension BatteryController {
    /// A bounded reversible power-flow test. A successful SMC write alone never
    /// qualifies the hardware; the policy can request this test automatically.
    func beginQualification() -> Bool {
        guard qualification == nil, state.operation == nil else {
            snapshot.reason = .busy
            return false
        }
        snapshot.competitors = readCompetitors()
        guard snapshot.competitors.isEmpty else { snapshot.reason = .conflict; return false }
        probe()
        guard hardware != nil, validSampleForAction(),
              let percent = snapshot.sample?.percent, (20...100).contains(percent) else {
            snapshot.reason = .unavailable
            return false
        }
        state.chargeQualified = false
        state.dischargeQualified = false
        state.ownsHardware = true
        guard save() else { return false }
        let deferCharge = percent == 100 || state.policy.enabled && percent > state.policy.lower
        qualification = BatteryQualification(stage: deferCharge ? 1 : 0,
                                             chargeDeferred: deferCharge)
        qualificationCommand(deferCharge ? .hold : .charge)
        return qualification != nil
    }

    func qualificationTick() {
        guard let test = qualification else { return }
        if pauseQualificationForUnplug() { return }
        guard !sleeping, snapshot.competitors.isEmpty,
              let sample = snapshot.sample, sample.isFresh(at: Date()),
              sample.connected == true, sample.percent! > 15,
              sample.temperature! < state.policy.heatCutoff else { fail(.verificationFailed); return }
        guard checkOwnership() else { return }
        snapshot.reason = .qualifying
        let elapsed = Date().timeIntervalSince(test.began)
        guard elapsed >= 10 else { return }
        // macOS may refuse a recharge test while its gauge still shows 100%.
        // The full-battery path verifies hold/discharge now and charging later.
        let timeout = test.stage == 3 && test.chargeDeferred ? 300 : 90
        guard elapsed < Double(timeout) else { fail(.verificationFailed); return }
        if test.lastSample == sample.at { return }
        qualification?.lastSample = sample.at
        let matches = qualificationMatches(test.stage, sample)
        qualification?.matches = matches ? test.matches + 1 : 0
        if (qualification?.matches ?? 0) >= 3 {
            advanceQualification()
        }
    }

    private func pauseQualificationForUnplug() -> Bool {
        guard snapshot.sample?.isFresh(at: Date()) == true,
              snapshot.sample?.connected == false else { return false }
        qualification = nil
        _ = restoreHardware(disable: false)
        snapshot.reason = state.recoveryPending ? .recovery : .unplugged
        return true
    }

    private func qualificationMatches(_ stage: Int, _ sample: BatterySample) -> Bool {
        let watts = sample.watts ?? .nan
        switch stage {
        case 0, 3: return sample.charging == true && watts > 1
        case 1: return sample.charging == false && watts <= 0.8
        default: return sample.charging == false && watts < -1
        }
    }

    private func advanceQualification() {
        guard let test = qualification else { return }
        let stage = test.stage
        state.record(.qualifying, at: Date(), detail: "stage=\(stage), watts=\(snapshot.sample?.watts ?? 0)")
        if stage == 2 && test.chargeDeferred {
            finishDischargeQualification()
            return
        }
        if stage == 3 {
            qualification = nil
            if hardware?.backendName != "native-owned-policy" || !state.policy.enabled {
                guard restoreHardware(disable: false) else { return }
            }
            state.qualifiedFingerprint = snapshot.fingerprint
            state.chargeQualified = true
            state.dischargeQualified = true
            state.qualificationFailures = 0
            state.nextQualificationAt = nil
            _ = save()
            tick()
            return
        }
        qualification = BatteryQualification(stage: stage + 1,
                                             chargeDeferred: test.chargeDeferred)
        qualificationCommand(stage == 0 ? .hold : stage == 1 ? .discharge : .charge)
    }

    private func finishDischargeQualification() {
        qualification = nil
        state.qualifiedFingerprint = snapshot.fingerprint
        state.dischargeQualified = true
        state.qualificationFailures = 0
        state.nextQualificationAt = nil
        guard save() else { return }
        if state.policy.enabled { tick() }
        else { _ = restoreHardware(disable: false) }
    }

    func beginChargeQualification() -> Bool {
        guard qualification == nil, state.dischargeQualified, !state.chargeQualified,
              (state.qualificationFailures ?? 0) < 3,
              Date() >= state.nextQualificationAt ?? .distantPast,
              let percent = snapshot.sample?.percent, percent <= state.policy.lower else { return false }
        if hardware == nil { probe() }
        guard hardware != nil else { snapshot.reason = .unavailable; return false }
        state.ownsHardware = true
        guard save() else { return false }
        qualification = BatteryQualification(stage: 3, chargeDeferred: true)
        qualificationCommand(.charge)
        return qualification != nil
    }

    private func qualificationCommand(_ command: BatteryCommand) {
        do {
            guard let hardware else { throw BatteryHardwareError.unavailable }
            hardware.prepare(upper: state.policy.enabled ? state.policy.upper : 100, target: max(1, (snapshot.sample?.percent ?? 20) - 2))
            try hardware.apply(command)
            snapshot.command = command
            snapshot.reason = .qualifying
        } catch { fail(.writeFailed, detail: String(describing: error)) }
    }
}

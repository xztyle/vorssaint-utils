// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import Foundation

struct BatteryQualification {
    var stage = 0
    var began = Date()
    var matches = 0
    var lastSample: Date?
}

extension BatteryController {
    /// An explicit user action. It performs a bounded reversible power-flow test;
    /// a successful write/readback alone never qualifies the hardware.
    func beginQualification() -> Bool {
        guard qualification == nil, state.operation == nil, !state.policy.enabled else {
            snapshot.reason = .busy
            return false
        }
        snapshot.competitors = readCompetitors()
        guard snapshot.competitors.isEmpty else { snapshot.reason = .conflict; return false }
        probe()
        guard hardware != nil, validSampleForAction(),
              let percent = snapshot.sample?.percent, (20...90).contains(percent) else {
            snapshot.reason = .unavailable
            return false
        }
        state.chargeQualified = false
        state.dischargeQualified = false
        state.ownsHardware = true
        guard save() else { return false }
        qualification = BatteryQualification()
        qualificationCommand(.charge)
        return qualification != nil
    }

    func qualificationTick() {
        guard let test = qualification else { return }
        guard !sleeping, snapshot.competitors.isEmpty,
              let sample = snapshot.sample, sample.isFresh(at: Date()),
              sample.connected == true, sample.percent! > 15,
              sample.temperature! < state.policy.heatCutoff else { fail(.verificationFailed); return }
        guard checkOwnership() else { return }
        snapshot.reason = .qualifying
        let elapsed = Date().timeIntervalSince(test.began)
        guard elapsed >= 10 else { return }
        guard elapsed < 90 else { fail(.verificationFailed); return }
        if test.lastSample == sample.at { return }
        qualification?.lastSample = sample.at
        let watts = sample.watts ?? .nan
        let matches: Bool
        switch test.stage {
        case 0, 3: matches = sample.charging == true && watts > 1
        case 1: matches = sample.charging == false && watts <= 0.8
        default: matches = sample.charging == false && watts < -1
        }
        qualification?.matches = matches ? test.matches + 1 : 0
        if (qualification?.matches ?? 0) >= 3 { advanceQualification() }
    }

    private func advanceQualification() {
        guard let stage = qualification?.stage else { return }
        state.record(.qualifying, at: Date(), detail: "stage=\(stage), watts=\(snapshot.sample?.watts ?? 0)")
        if stage == 3 {
            qualification = nil
            guard restoreHardware(disable: true) else { return }
            state.qualifiedFingerprint = snapshot.fingerprint
            state.chargeQualified = true
            state.dischargeQualified = true
            _ = save()
            return
        }
        qualification = BatteryQualification(stage: stage + 1)
        qualificationCommand(stage == 0 ? .hold : stage == 1 ? .discharge : .charge)
    }

    private func qualificationCommand(_ command: BatteryCommand) {
        do {
            try hardware?.apply(command)
            snapshot.command = command
            snapshot.reason = .qualifying
        } catch { fail(.writeFailed, detail: String(describing: error)) }
    }
}

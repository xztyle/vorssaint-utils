// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import Foundation

/// Pure policy. Only the daemon translates a decision into hardware writes.
enum BatteryPolicy {
    static func decide(state: inout BatteryCareState, sample: BatterySample?,
                       now: Date, sleeping: Bool = false) -> BatteryDecision {
        if state.recoveryPending { return .init(command: .system, reason: .recovery) }
        guard (state.policy.enabled && !state.scheduledPause) || state.operation != nil else {
            return .init(command: .system, reason: .system)
        }
        guard let sample, sample.isFresh(at: now) else {
            pauseOperation(&state)
            return .init(command: .hold, reason: .staleSensor)
        }
        if sample.connected == false { return disconnected(&state) }
        if sleeping {
            pauseOperation(&state)
            return .init(command: .hold, reason: .sleeping)
        }
        if let thermal = thermalDecision(&state, temperature: sample.temperature!, now: now) {
            return thermal
        }
        if state.operation != nil { return operationDecision(&state, sample: sample, now: now) }
        return normalDecision(&state, percent: sample.percent!, now: now)
    }

    static func begin(_ kind: BatteryOperationKind, target: Int = 10,
                      state: inout BatteryCareState, now: Date) -> Bool {
        guard state.operation == nil, (10...99).contains(target) else { return false }
        state.operation = BatteryOperation(kind: kind, savedPolicy: state.policy,
                                           startedAt: now, phaseStartedAt: now, target: target)
        state.dischargeStarted = nil
        return true
    }

    static func pauseOperation(_ state: inout BatteryCareState) {
        if state.operation?.kind == .calibration || state.operation?.kind == .discharge {
            state.operation?.paused = true
        }
        state.dischargeStarted = nil
        state.lastTick = nil
    }

    private static func disconnected(_ state: inout BatteryCareState) -> BatteryDecision {
        if state.operation?.kind == .topUp || state.operation?.kind == .discharge {
            state.cancelOperation()
        } else { pauseOperation(&state) }
        state.chargingLatch = false
        return .init(command: .system, reason: .unplugged)
    }

    private static func thermalDecision(_ state: inout BatteryCareState,
                                        temperature: Double, now: Date) -> BatteryDecision? {
        if temperature >= state.policy.heatCutoff {
            state.heatLatched = true
            state.coolSince = nil
        }
        guard state.heatLatched else { return nil }
        state.dischargeStarted = nil
        if temperature <= state.policy.heatResume {
            if state.coolSince == nil { state.coolSince = now }
            if now.timeIntervalSince(state.coolSince!) >= 60 {
                state.heatLatched = false
                state.coolSince = nil
                return nil
            }
        } else { state.coolSince = nil }
        return .init(command: .hold, reason: temperature <= state.policy.heatResume ? .cooling : .heat)
    }

    private static func normalDecision(_ state: inout BatteryCareState,
                                       percent: Int, now: Date) -> BatteryDecision {
        guard state.policy.enabled else { return .init(command: .system, reason: .system) }
        if state.policy.automaticDischarge && percent > state.policy.upper {
            return boundedDischarge(&state, percent: percent, target: state.policy.upper, now: now)
        }
        state.dischargeStarted = nil
        if percent >= state.policy.upper { state.chargingLatch = false }
        if percent <= state.policy.lower { state.chargingLatch = true }
        return .init(command: state.chargingLatch ? .charge : .hold,
                     reason: state.chargingLatch ? .charging : .holding)
    }

    private static func boundedDischarge(_ state: inout BatteryCareState, percent: Int,
                                         target: Int, now: Date) -> BatteryDecision {
        if percent <= max(10, target) {
            state.dischargeStarted = nil
            return .init(command: .hold, reason: .holding)
        }
        if state.dischargeStarted == nil { state.dischargeStarted = now }
        guard (0..<6 * 3600).contains(now.timeIntervalSince(state.dischargeStarted!)) else {
            state.cancelOperation()
            state.policy.automaticDischarge = false
            return .init(command: .hold, reason: .timeout)
        }
        return .init(command: .discharge, reason: .discharging)
    }

    private static func operationDecision(_ state: inout BatteryCareState,
                                          sample: BatterySample, now: Date) -> BatteryDecision {
        guard let operation = state.operation else { return .init(command: .hold, reason: .holding) }
        if operation.paused { return .init(command: .hold, reason: .paused) }
        if operation.kind == .topUp { return .init(command: .charge, reason: .topUp) }
        guard (0..<48 * 3600).contains(now.timeIntervalSince(operation.startedAt)) else {
            state.cancelOperation()
            return .init(command: .hold, reason: .timeout)
        }
        if operation.kind == .discharge {
            if sample.percent! <= operation.target {
                state.cancelOperation()
                return normalDecision(&state, percent: sample.percent!, now: now)
            }
            return boundedDischarge(&state, percent: sample.percent!, target: operation.target, now: now)
        }
        return calibrationDecision(&state, sample: sample, now: now)
    }

    private static func calibrationDecision(_ state: inout BatteryCareState,
                                            sample: BatterySample, now: Date) -> BatteryDecision {
        switch state.operation!.phase {
        case .charge, .recharge:
            if sample.percent! >= 100 && sample.charging == false {
                let next: BatteryCalibrationPhase = state.operation!.phase == .charge ? .discharge : .hold
                state.operation?.phase = next
                state.operation?.phaseStartedAt = now
                state.lastTick = now
                return calibrationDecision(&state, sample: sample, now: now)
            }
            return .init(command: .charge, reason: .calibration)
        case .discharge:
            if sample.percent! <= 10 {
                state.dischargeStarted = nil
                state.operation?.phase = .recharge
                state.operation?.phaseStartedAt = now
                return .init(command: .charge, reason: .calibration)
            }
            return boundedDischarge(&state, percent: sample.percent!, target: 10, now: now)
        case .hold: return calibrationHold(&state, sample: sample, now: now)
        }
    }

    private static func calibrationHold(_ state: inout BatteryCareState,
                                        sample: BatterySample, now: Date) -> BatteryDecision {
        let elapsed = state.lastTick.map { now.timeIntervalSince($0) } ?? 0
        if (0...20).contains(elapsed), sample.percent! >= 99 {
            state.operation!.holdSeconds += elapsed
        }
        state.lastTick = now
        if state.operation!.holdSeconds >= 3600 {
            state.cancelOperation()
            return normalDecision(&state, percent: sample.percent!, now: now)
        }
        return .init(command: .charge, reason: .calibration)
    }
}

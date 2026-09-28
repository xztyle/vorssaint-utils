// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import Foundation

final class BatteryController {
    let queue = DispatchQueue(label: BatteryCareIdentifiers.helperID)
    let journal: BatteryStateStore
    let makeHardware: () throws -> BatteryHardware
    let readSample: () -> BatterySample?
    let readCompetitors: () -> [String]
    var state: BatteryCareState
    var hardware: BatteryHardware?
    var snapshot = BatteryCareSnapshot()
    var timer: DispatchSourceTimer?
    var sleeping = false
    var qualification: BatteryQualification?
    var lastCommandAt = Date()
    var tickNumber = 0
    var lastSaved = Date.distantPast

    init(journal: BatteryStateStore, automaticallyStart: Bool = true,
         makeHardware: @escaping () throws -> BatteryHardware = { try BatteryHardware() },
         readSample: @escaping () -> BatterySample? = BatterySensor.sample,
         readCompetitors: @escaping () -> [String] = BatteryCompetitors.running,
         fingerprint: String = BatteryHardware.fingerprint) {
        self.journal = journal
        self.makeHardware = makeHardware
        self.readSample = readSample
        self.readCompetitors = readCompetitors
        state = Self.load(journal)
        snapshot.fingerprint = fingerprint
        snapshot.helperBuild = BatteryCareIdentifiers.protocolVersion
        if state.qualifiedFingerprint != snapshot.fingerprint {
            state.chargeQualified = false
            state.dischargeQualified = false
        }
        BatteryPolicy.pauseOperation(&state)
        state.operation?.paused = true
        if automaticallyStart { queue.async { self.start() } }
    }

    private static func load(_ journal: BatteryStateStore) -> BatteryCareState {
        do { return try journal.load() }
        catch {
            var state = BatteryCareState()
            state.ownsHardware = true
            state.recoveryPending = true
            state.record(.journalFailed, at: Date())
            return state
        }
    }

    func start() {
        probe()
        if state.ownsHardware { _ = restoreHardware(disable: false) }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 5)
        timer.setEventHandler { [weak self] in self?.tick() }
        self.timer = timer
        timer.resume()
    }

    func probe() {
        do {
            hardware = try makeHardware()
            snapshot.chargeCandidate = true
            snapshot.dischargeCandidate = true
        } catch {
            hardware = nil
            snapshot.diagnostic = String(describing: error)
            snapshot.chargeCandidate = false
            snapshot.dischargeCandidate = false
        }
    }

    func status(_ reply: @escaping (Data) -> Void) {
        queue.async { reply(self.response(true)) }
    }

    func request(_ data: Data, reply: @escaping (Data) -> Void) {
        queue.async {
            guard let request = BatteryCareIPC.decodeRequest(data) else {
                self.snapshot.reason = .invalidRequest
                reply(self.response(false))
                return
            }
            let success = self.handle(request)
            reply(self.response(success))
        }
    }

    func response(_ success: Bool) -> Data {
        snapshot.state = state
        snapshot.qualificationStep = qualification?.stage
        return BatteryCareIPC.encode(.init(succeeded: success, snapshot: snapshot))
    }

    func handle(_ request: BatteryCareRequest) -> Bool {
        if request.kind == .returnToSystem {
            qualification = nil
            state.cancelOperation()
            state.policy.enabled = false
            return restoreHardware(disable: true)
        }
        if request.kind == .cancel {
            qualification = nil
            state.cancelOperation()
            guard restoreHardware(disable: false) else { return false }
            tick()
            return true
        }
        guard !state.recoveryPending else { snapshot.reason = .recovery; return false }
        if request.kind == .qualify { return beginQualification() }
        guard qualification == nil else { snapshot.reason = .busy; return false }
        if request.kind == .configure { return configure(request.policy!) }
        return startOperation(request)
    }

    func configure(_ policy: BatteryCarePolicy) -> Bool {
        guard state.operation == nil else { snapshot.reason = .busy; return false }
        guard !policy.enabled || canControl(discharge: policy.automaticDischarge) else { return false }
        state.policy = policy
        state.scheduledPause = false
        state.chargingLatch = false
        if !policy.enabled { return restoreHardware(disable: true) }
        guard save() else { return false }
        tick()
        return !state.recoveryPending
    }

    func startOperation(_ request: BatteryCareRequest) -> Bool {
        let discharge = request.kind == .discharge || request.kind == .calibrate
            || (request.kind == .resume && state.operation?.kind != .topUp)
        guard canControl(discharge: discharge), validSampleForAction() else { return false }
        if request.kind == .resume {
            guard state.operation?.paused == true else { snapshot.reason = .invalidRequest; return false }
            state.operation?.paused = false
            state.lastTick = nil
        } else {
            let kinds: [BatteryRequestKind: BatteryOperationKind] = [
                .discharge: .discharge, .topUp: .topUp, .calibrate: .calibration]
            guard let kind = kinds[request.kind], BatteryPolicy.begin(kind, target: request.target ?? 10,
                state: &state, now: Date()) else { snapshot.reason = .busy; return false }
        }
        guard save() else { return false }
        tick()
        return !state.recoveryPending
    }

    func canControl(discharge: Bool) -> Bool {
        snapshot.competitors = readCompetitors()
        guard snapshot.competitors.isEmpty else { snapshot.reason = .conflict; return false }
        guard hardware != nil, state.chargeQualified, !discharge || state.dischargeQualified else {
            snapshot.reason = .unavailable
            return false
        }
        return true
    }

    func validSampleForAction() -> Bool {
        snapshot.sample = readSample()
        guard let sample = snapshot.sample, sample.isFresh(at: Date()), sample.connected == true,
              sample.temperature! < state.policy.heatCutoff else {
            snapshot.reason = .staleSensor
            return false
        }
        return true
    }

    func tick() {
        snapshot.sample = readSample()
        tickNumber += 1
        if tickNumber % 6 == 1 { snapshot.competitors = readCompetitors() }
        if state.recoveryPending { _ = restoreHardware(disable: true); return }
        if qualification != nil { qualificationTick(); return }
        guard state.policy.enabled || state.operation != nil else { return }
        guard snapshot.competitors.isEmpty else { fail(.conflict); return }
        guard state.chargeQualified else { fail(.unavailable); return }
        if !checkOwnership() { return }
        runSchedules()
        let previous = state
        let decision = BatteryPolicy.decide(state: &state, sample: snapshot.sample, now: Date(), sleeping: sleeping)
        if decision.command == .discharge && !state.dischargeQualified { fail(.unavailable); return }
        if previous != state, !save() { return }
        enact(decision)
        verifyPowerFlow()
    }

    func checkOwnership() -> Bool {
        guard state.ownsHardware else { return true }
        do { try hardware?.verifyOwnership(); return hardware != nil }
        catch { fail(.conflict, detail: String(describing: error)); return false }
    }

    func enact(_ decision: BatteryDecision) {
        snapshot.reason = decision.reason
        state.record(decision.reason, at: Date())
        guard decision.command != snapshot.command || !state.ownsHardware else { return }
        if decision.command == .system { _ = restoreHardware(disable: false); return }
        state.ownsHardware = true
        guard save() else { return }
        do {
            guard let hardware else { throw BatteryHardwareError.unavailable }
            try hardware.apply(decision.command)
            snapshot.command = decision.command
            lastCommandAt = Date()
        } catch { fail(.writeFailed, detail: String(describing: error)) }
    }

    func verifyPowerFlow() {
        guard Date().timeIntervalSince(lastCommandAt) >= 40,
              let sample = snapshot.sample, sample.isFresh(at: Date()) else { return }
        if snapshot.command == .discharge && (sample.watts ?? 0) >= -0.5 {
            fail(.verificationFailed)
        }
        if snapshot.command == .hold && sample.charging == true && (sample.watts ?? 0) > 1 {
            fail(.verificationFailed)
        }
    }

    @discardableResult func restoreHardware(disable: Bool) -> Bool {
        if disable { state.policy.enabled = false }
        guard state.ownsHardware || state.recoveryPending else {
            if disable { snapshot.reason = .system; snapshot.command = .system }
            return save()
        }
        state.recoveryPending = true
        _ = save()
        if hardware == nil { probe() }
        do {
            guard let hardware else { throw BatteryHardwareError.unavailable }
            try hardware.apply(.system)
            state.ownsHardware = false
            state.recoveryPending = false
            snapshot.command = .system
            snapshot.reason = .system
            return save()
        } catch {
            snapshot.reason = .recovery
            snapshot.diagnostic = String(describing: error)
            state.record(.recovery, at: Date(), detail: snapshot.diagnostic)
            _ = save()
            return false
        }
    }

    func fail(_ reason: BatteryReason, detail: String? = nil) {
        qualification = nil
        state.cancelOperation()
        state.policy.enabled = false
        state.record(reason, at: Date(), detail: detail)
        if reason == .writeFailed || reason == .verificationFailed {
            state.chargeQualified = false
            state.dischargeQualified = false
        }
        _ = restoreHardware(disable: true)
        snapshot.reason = state.recoveryPending ? .recovery : reason
        snapshot.diagnostic = detail
        _ = save()
    }

    @discardableResult func save() -> Bool {
        do { try journal.save(state); lastSaved = Date(); return true }
        catch {
            snapshot.reason = .journalFailed
            snapshot.diagnostic = String(describing: error)
            // The previous on-disk ownership record remains. Never issue a new
            // control command after a failed durable write; retry restoration.
            state.recoveryPending = state.ownsHardware || state.recoveryPending
            state.policy.enabled = false
            return false
        }
    }

    func powerChange(sleep: Bool) {
        queue.sync {
            sleeping = sleep
            if sleep {
                if qualification != nil { _ = restoreHardware(disable: true) }
                qualification = nil
                BatteryPolicy.pauseOperation(&state)
                if state.ownsHardware { enact(.init(command: .hold, reason: .sleeping)) }
                _ = save()
            } else { tick() }
        }
    }

    func shutdown(_ completion: @escaping (Bool) -> Void) {
        queue.async {
            self.qualification = nil
            BatteryPolicy.pauseOperation(&self.state)
            let restored = self.restoreHardware(disable: false)
            completion(restored)
        }
    }
}

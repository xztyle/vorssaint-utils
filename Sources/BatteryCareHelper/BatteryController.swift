// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import Foundation

final class BatteryController {
    let queue = DispatchQueue(label: BatteryCareIdentifiers.helperID)
    let journal: BatteryStateStore
    var makeHardware: () throws -> any BatteryChargeHardware = { try BatteryHardware() }
    let readSample: () -> BatterySample?
    let readCompetitors: () -> [String]
    var state: BatteryCareState
    var hardware: (any BatteryChargeHardware)?
    var snapshot = BatteryCareSnapshot()
    var timer: DispatchSourceTimer?
    var sleeping = false
    var qualification: BatteryQualification?
    var lastCommandAt = Date()
    var flowFailureSamples = 0
    var lastFlowSampleAt: Date?
    var lastConfirmedDischargeAt = Date()
    var lastFlowRawPercent: Double?
    var tickNumber = 0
    var lastSaved = Date.distantPast
    var lastAdapterPresence: Bool?

    init(journal: BatteryStateStore, automaticallyStart: Bool = true,
         makeHardware: (() throws -> any BatteryChargeHardware)? = nil,
         readSample: @escaping () -> BatterySample? = BatterySensor.sample,
         readCompetitors: @escaping () -> [String] = BatteryCompetitors.running,
         fingerprint: String = BatteryHardware.fingerprint) {
        self.journal = journal
        self.readSample = readSample
        self.readCompetitors = readCompetitors
        state = Self.load(journal)
        snapshot.fingerprint = fingerprint
        snapshot.helperBuild = BatteryCareIdentifiers.protocolVersion
        if state.qualifiedFingerprint != fingerprint + " · native-owned-policy:v1" { invalidateQualificationIfChanged() }
        BatteryPolicy.pauseOperation(&state)
        state.operation?.paused = true
        self.makeHardware = makeHardware ?? { [weak self] in
            guard let self else { throw BatteryHardwareError.unavailable }
            return try self.defaultHardware()
        }
        if automaticallyStart { queue.async { self.start() } }
    }

    func invalidateQualificationIfChanged() {
        guard state.qualifiedFingerprint != snapshot.fingerprint else { return }
        state.chargeQualified = false
        state.dischargeQualified = false
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
        if !resumeNativeLeaseAtStart(), state.ownsHardware || state.nativeLease != nil {
            state.ownsHardware = true; _ = restoreHardware(disable: false)
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 5)
        timer.setEventHandler { [weak self] in self?.tick() }
        self.timer = timer
        timer.resume()
    }

    func probe() {
        do {
            hardware = try makeHardware()
            snapshot.controlBackend = hardware?.backendName
            if snapshot.controlBackend == "native-owned-policy", !snapshot.fingerprint.hasSuffix(" · native-owned-policy:v1") {
                snapshot.fingerprint += " · native-owned-policy:v1"
            }
            invalidateQualificationIfChanged()
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
            state.qualificationFailures = 0
            state.nextQualificationAt = nil
            return restoreHardware(disable: true)
        }
        if request.kind == .cancel {
            if qualification != nil { state.policy.enabled = false }
            qualification = nil
            state.cancelOperation()
            state.qualificationFailures = 0
            state.nextQualificationAt = nil
            guard restoreHardware(disable: false) else { return false }
            tick()
            return true
        }
        guard !state.recoveryPending else { snapshot.reason = .recovery; return false }
        if request.kind == .qualify {
            state.qualificationFailures = 0
            state.nextQualificationAt = nil
            return beginQualification()
        }
        if request.kind == .configure { return configure(request.policy!) }
        guard qualification == nil else { snapshot.reason = .busy; return false }
        return startOperation(request)
    }

    func configure(_ policy: BatteryCarePolicy) -> Bool {
        guard state.operation == nil else { snapshot.reason = .busy; return false }
        if policy.enabled {
            snapshot.competitors = readCompetitors()
            guard snapshot.competitors.isEmpty else { snapshot.reason = .conflict; return false }
        }
        if qualification != nil && policy != state.policy {
            qualification = nil
            guard restoreHardware(disable: false) else { return false }
        }
        state.policy = policy
        state.scheduledPause = false
        state.chargingLatch = false
        state.qualificationFailures = 0
        state.nextQualificationAt = nil
        if !policy.enabled {
            qualification = nil
            return restoreHardware(disable: true)
        }
        guard save() else { return false }
        tick()
        return true
    }

    func startOperation(_ request: BatteryCareRequest) -> Bool {
        let discharge = request.kind == .discharge || request.kind == .calibrate
            || (request.kind == .resume && state.operation?.kind != .topUp)
        let dischargeOnly = request.kind == .discharge
            || request.kind == .resume && state.operation?.kind == .discharge
        guard canControl(discharge: discharge, charge: !dischargeOnly), validSampleForAction() else { return false }
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

    func canControl(discharge: Bool, charge: Bool = true) -> Bool {
        snapshot.competitors = readCompetitors()
        guard snapshot.competitors.isEmpty else { snapshot.reason = .conflict; return false }
        guard hardware != nil, !charge || state.chargeQualified, !discharge || state.dischargeQualified else {
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
        refreshSample()
        tickNumber += 1
        if tickNumber % 6 == 1 { snapshot.competitors = readCompetitors() }
        if state.recoveryPending { _ = restoreHardware(disable: false); return }
        if qualification != nil { qualificationTick(); return }
        guard state.policy.enabled || state.operation != nil else { return }
        guard snapshot.competitors.isEmpty else {
            if state.ownsHardware { fail(.conflict) }
            else { snapshot.reason = .conflict }
            return
        }
        guard state.chargeQualified || state.dischargeQualified else {
            retryQualification()
            return
        }
        if !checkOwnership() { return }
        applyPolicyDecision()
    }

    private func refreshSample() {
        snapshot.sample = readSample()
        guard let sample = snapshot.sample, sample.isFresh(at: Date()),
              let connected = sample.connected else { return }
        defer { lastAdapterPresence = connected }
        guard connected, lastAdapterPresence == false else { return }
        state.qualificationFailures = 0
        state.nextQualificationAt = nil
        _ = save()
    }

    private func applyPolicyDecision() {
        runSchedules()
        let previous = state
        let decision = BatteryPolicy.decide(state: &state, sample: snapshot.sample, now: Date(), sleeping: sleeping)
        if decision.command == .charge && !state.chargeQualified {
            if !beginChargeQualification() {
                let fallback: BatteryCommand = (state.qualificationFailures ?? 0) >= 3 ? .system : .hold
                enact(.init(command: fallback, reason: .unavailable))
            }
            return
        }
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
        prepareHardware()
        guard decision.command != snapshot.command || !state.ownsHardware || hardware?.needsApply(decision.command) == true else { return }
        if decision.command == .system { _ = restoreHardware(disable: false); return }
        state.ownsHardware = true
        guard save() else { return }
        do {
            guard let hardware else { throw BatteryHardwareError.unavailable }
            try hardware.apply(decision.command)
            snapshot.command = decision.command
            lastCommandAt = Date()
            flowFailureSamples = 0
            lastFlowSampleAt = nil
            lastConfirmedDischargeAt = Date()
            lastFlowRawPercent = snapshot.sample?.rawPercent
        } catch { fail(.writeFailed, detail: String(describing: error)) }
    }

    func verifyPowerFlow() {
        guard Date().timeIntervalSince(lastCommandAt) >= 40,
              let sample = snapshot.sample, sample.isFresh(at: Date()),
              sample.at != lastFlowSampleAt else { return }
        lastFlowSampleAt = sample.at
        if snapshot.command == .discharge {
            verifyDischargeFlow(sample)
            return
        }
        let holdFailed = snapshot.command == .hold && sample.charging == true && (sample.watts ?? 0) > 1
        flowFailureSamples = holdFailed ? flowFailureSamples + 1 : 0
        if flowFailureSamples >= 3 { fail(.verificationFailed) }
    }

    private func verifyDischargeFlow(_ sample: BatterySample) {
        let rawDrop = sample.rawPercent.flatMap { raw in
            lastFlowRawPercent.map { raw < $0 - 0.02 }
        } ?? false
        if (sample.watts ?? 0) < -0.5 || rawDrop {
            lastConfirmedDischargeAt = Date()
            lastFlowRawPercent = sample.rawPercent
            flowFailureSamples = 0
            return
        }
        flowFailureSamples += 1
        if flowFailureSamples >= 3 && Date().timeIntervalSince(lastConfirmedDischargeAt) >= 90 {
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
            flowFailureSamples = 0
            lastFlowSampleAt = nil
            lastFlowRawPercent = nil
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
        let wasControlling = qualification != nil || state.policy.enabled
        let chargeOnlyTest = qualification?.stage == 3 && qualification?.chargeDeferred == true
        qualification = nil
        state.cancelOperation()
        state.record(reason, at: Date(), detail: detail)
        if reason == .writeFailed || reason == .verificationFailed {
            state.chargeQualified = false
            if !chargeOnlyTest { state.dischargeQualified = false }
        }
        if wasControlling { postponeQualification() }
        _ = restoreHardware(disable: false)
        snapshot.reason = state.recoveryPending ? .recovery : reason
        snapshot.diagnostic = detail
        _ = save()
    }

    func retryQualification() {
        if snapshot.sample?.isFresh(at: Date()) == true, snapshot.sample?.connected == false {
            snapshot.reason = .unplugged
            return
        }
        guard !sleeping, (state.qualificationFailures ?? 0) < 3 else {
            snapshot.reason = .unavailable
            return
        }
        guard Date() >= state.nextQualificationAt ?? .distantPast else {
            snapshot.reason = .qualifying
            return
        }
        _ = beginQualification()
    }

    func postponeQualification() {
        let failures = min(3, (state.qualificationFailures ?? 0) + 1)
        state.qualificationFailures = failures
        let delay: TimeInterval = [0, 60, 300, 0][failures]
        state.nextQualificationAt = delay > 0 ? Date().addingTimeInterval(delay) : nil
    }

    @discardableResult func save() -> Bool {
        do { try journal.save(state); lastSaved = Date(); return true }
        catch {
            snapshot.reason = .journalFailed
            snapshot.diagnostic = String(describing: error)
            // The previous on-disk ownership record remains. Never issue a new
            // control command after a failed durable write; retry restoration.
            state.recoveryPending = state.ownsHardware || state.recoveryPending
            return false
        }
    }

    func powerChange(sleep: Bool) {
        queue.sync {
            sleeping = sleep
            if sleep {
                if qualification != nil { _ = restoreHardware(disable: false) }
                qualification = nil
                BatteryPolicy.pauseOperation(&state)
                let active = state.policy.enabled && !state.scheduledPause || state.operation != nil
                if state.ownsHardware || active && canControl(discharge: false) {
                    enact(.init(command: .hold, reason: .sleeping))
                }
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

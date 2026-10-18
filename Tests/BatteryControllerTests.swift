// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import Foundation

enum BatteryControllerTests {
    static func run(_ suite: TestSuite) {
        restoreRetry(suite)
        journalFailure(suite)
        drift(suite)
        restart(suite)
        sleepBeforeFirstTick(suite)
        qualification(suite)
        qualificationFromFull(suite)
        qualificationFullGaugeFallback(suite)
        policyFromFullDischargesThenCharges(suite)
        policyAboveLowerLimitDefersChargingTest(suite)
        qualificationFullTimeout(suite)
        qualificationUnplug(suite)
        savedPolicyStartsAndRecovers(suite)
        failedPolicyCanRetry(suite)
        failedTestsRecoverOnReplug(suite)
        transientFlowReading(suite)
        disablingDuringTest(suite)
        changingPolicyDuringTest(suite)
        dischargeUnplug(suite)
        partialDischargeCapability(suite)
        badRequest(suite)
    }

    static func fixture(_ store: MemoryBatteryStore, _ transport: FakeBatteryTransport,
                        competitors: @escaping () -> [String] = { [] },
                        adapterPresent: @escaping () -> Bool = { true },
                        percent: @escaping () -> Int = { 60 },
                        fullyCharged: @escaping () -> Bool? = { nil },
                        rawPercent: @escaping () -> Double? = { nil }) -> BatteryController {
        var readingNumber = 0
        let time = Date()
        return BatteryController(journal: store, automaticallyStart: false,
            makeHardware: { try BatteryHardware(transport: transport) }, readSample: {
                let discharge = transport.values["CHIE"] == [8]
                let charge = !discharge && transport.values["CHTE"] == [0, 0, 0, 0]
                readingNumber += 1
                let connected = adapterPresent()
                let adapterDetails: [String: Any] = connected ? ["Watts": 68] : ["FamilyCode": 0]
                let properties: [String: Any] = ["CurrentCapacity": percent(), "MaxCapacity": 100, "Temperature": 3032,
                    "AppleRawExternalConnected": connected && !discharge,
                    "ExternalConnected": connected && !discharge,
                    "AdapterDetails": adapterDetails,
                    "IsCharging": connected && charge, "Voltage": 10000,
                    "Amperage": !connected || discharge ? -1000 : charge ? 1000 : 0]
                var reading = properties
                if let fullyCharged = fullyCharged() { reading["FullyCharged"] = fullyCharged }
                if let rawPercent = rawPercent() {
                    reading["AppleRawCurrentCapacity"] = Int(rawPercent * 100)
                    reading["AppleRawMaxCapacity"] = 10_000
                }
                return BatterySensor.decode(reading, at: time.addingTimeInterval(Double(readingNumber) / 1000))
            }, readCompetitors: competitors, fingerprint: "fixture")
    }

    static func restoreRetry(_ suite: TestSuite) {
        let store = MemoryBatteryStore()
        store.state.ownsHardware = true
        let transport = FakeBatteryTransport()
        transport.values["CHIE"] = [8]
        transport.denyWrites = true
        let controller = fixture(store, transport)
        controller.probe()
        suite.expect(!controller.restoreHardware(disable: true), "failed return is reported as failed")
        suite.expect(store.state.recoveryPending && store.state.ownsHardware,
                     "failed restore retains durable recovery authority")
        transport.denyWrites = false
        controller.tick()
        suite.expect(!store.state.recoveryPending && !store.state.ownsHardware,
                     "watchdog retries and clears marker only after verified restore")
        suite.expect(transport.values["CHIE"] == [0], "retry restores adapter")
    }

    static func journalFailure(_ suite: TestSuite) {
        let store = MemoryBatteryStore()
        store.failWrites = true
        let transport = FakeBatteryTransport()
        let controller = fixture(store, transport)
        controller.probe()
        controller.enact(.init(command: .discharge, reason: .discharging))
        suite.expect(transport.values["CHIE"] == [0], "no adapter cut before durable ownership write")
        suite.expect(controller.snapshot.reason == .journalFailed, "journal failure visible")
    }

    static func drift(_ suite: TestSuite) {
        let store = MemoryBatteryStore()
        let transport = FakeBatteryTransport()
        let controller = fixture(store, transport)
        controller.probe()
        controller.enact(.init(command: .hold, reason: .holding))
        transport.values["CHTE"] = [0, 0, 0, 0]
        suite.expect(!controller.checkOwnership(), "unexpected SMC change loses ownership")
        suite.expect(!controller.state.ownsHardware && controller.snapshot.reason == .conflict,
                     "controller drift releases hardware instead of fighting it")
        let blocked = fixture(store, transport, competitors: { ["AlDente"] })
        suite.expect(!blocked.canControl(discharge: false), "known competitor refuses takeover")
    }

    static func restart(_ suite: TestSuite) {
        let store = MemoryBatteryStore()
        _ = BatteryPolicy.begin(.calibration, state: &store.state, now: Date())
        store.state.operation?.phase = .discharge
        let controller = fixture(store, FakeBatteryTransport())
        suite.expect(controller.state.operation?.paused == true, "daemon restart requires deliberate calibration resume")
        suite.expect(controller.state.operation?.phase == .discharge, "restart retains durable calibration phase")
        store.state.operation = nil
        _ = BatteryPolicy.begin(.topUp, state: &store.state, now: Date())
        let topUp = fixture(store, FakeBatteryTransport())
        suite.expect(topUp.state.operation?.paused == true, "restart cannot guess whether top-up unplug occurred")
        store.failReads = true
        let corrupt = fixture(store, FakeBatteryTransport())
        suite.expect(corrupt.state.recoveryPending, "corrupt journal triggers recovery instead of lost ownership")
    }

    static func sleepBeforeFirstTick(_ suite: TestSuite) {
        let store = MemoryBatteryStore()
        store.state.policy.enabled = true
        store.state.qualifiedFingerprint = "fixture"
        store.state.chargeQualified = true
        let transport = FakeBatteryTransport()
        let controller = fixture(store, transport)
        controller.probe()
        controller.powerChange(sleep: true)
        suite.expect(controller.snapshot.command == .hold && controller.state.ownsHardware,
                     "sleep claims hold for an enabled limit before the first timer tick")
        suite.expect(transport.values["CHTE"] == [1, 0, 0, 0] && store.state.ownsHardware,
                     "sleep hold is verified and durably owned")
        controller.powerChange(sleep: false)
        suite.expect(controller.snapshot.command == .charge && transport.values["CHTE"] == [0, 0, 0, 0],
                     "wake reevaluates the saved range and resumes charging below its lower bound")

        let blockedStore = MemoryBatteryStore()
        blockedStore.state = store.state
        blockedStore.state.ownsHardware = false
        let blockedTransport = FakeBatteryTransport()
        let blocked = fixture(blockedStore, blockedTransport, competitors: { ["AlDente"] })
        blocked.probe()
        blocked.powerChange(sleep: true)
        suite.expect(blockedTransport.writeCount == 0,
                     "sleep cannot claim battery control while another battery app runs")

        let inactiveTransport = FakeBatteryTransport()
        let inactive = fixture(MemoryBatteryStore(), inactiveTransport)
        inactive.probe()
        inactive.powerChange(sleep: true)
        suite.expect(inactiveTransport.writeCount == 0,
                     "sleep leaves the battery alone when care is disabled")
    }

    static func qualification(_ suite: TestSuite) {
        let store = MemoryBatteryStore()
        let transport = FakeBatteryTransport()
        let controller = fixture(store, transport)
        suite.expect(controller.beginQualification(), "explicit bounded qualification starts")
        for stage in 0...3 {
            controller.qualification?.began = Date().addingTimeInterval(-11)
            for _ in 0..<3 { controller.tick() }
            suite.expect(controller.qualification?.stage != stage, "measured stage \(stage) advances")
        }
        suite.expect(store.state.chargeQualified && store.state.dischargeQualified,
                     "charge and discharge unlock only after complete flow sequence")
        suite.expect(transport.values["CHIE"] == [0] && transport.values["CHTE"] == [0, 0, 0, 0],
                     "qualification restores system control")
    }

    static func qualificationFromFull(_ suite: TestSuite) {
        let store = MemoryBatteryStore()
        let transport = FakeBatteryTransport()
        let controller = fixture(store, transport, percent: { 100 }, fullyCharged: { true })
        suite.expect(controller.beginQualification() && controller.qualification?.stage == 1,
                     "full battery starts with a hold instead of an impossible charging measurement")
        controller.qualification?.began = Date().addingTimeInterval(-11)
        for _ in 0..<3 { controller.tick() }
        suite.expect(controller.qualification?.stage == 2 && transport.values["CHIE"] == [8],
                     "full-battery test starts measured discharge with charging inhibited")
        controller.qualification?.began = Date().addingTimeInterval(-11)
        for _ in 0..<3 { controller.tick() }
        suite.expect(controller.qualification == nil && !store.state.chargeQualified
            && store.state.dischargeQualified && !store.state.ownsHardware,
                     "full-battery test verifies discharge without forcing an impossible recharge")
    }

    static func qualificationFullGaugeFallback(_ suite: TestSuite) {
        var percent = 100
        let controller = fixture(MemoryBatteryStore(), FakeBatteryTransport(), percent: { percent })
        suite.expect(controller.beginQualification(), "full gauge fallback begins")
        for _ in 0..<2 {
            controller.qualification?.began = Date().addingTimeInterval(-11)
            for _ in 0..<3 { controller.tick() }
        }
        suite.expect(controller.qualification == nil && controller.state.dischargeQualified,
                     "rounded 100% does not block verified discharge control")
        percent = 98
        controller.tick()
        suite.expect(controller.qualification == nil,
                     "charge test waits for the user's lower charging limit")
    }

    static func policyFromFullDischargesThenCharges(_ suite: TestSuite) {
        var percent = 100
        let store = MemoryBatteryStore()
        let transport = FakeBatteryTransport()
        let controller = fixture(store, transport, percent: { percent })
        controller.probe()
        var policy = BatteryCarePolicy()
        policy.enabled = true
        suite.expect(controller.configure(policy), "policy is saved at full charge")
        for _ in 0..<2 {
            controller.qualification?.began = Date().addingTimeInterval(-11)
            for _ in 0..<3 { controller.tick() }
        }
        suite.expect(store.state.policy.enabled && store.state.dischargeQualified
            && !store.state.chargeQualified && controller.snapshot.command == .discharge,
            "verified discharge immediately starts toward the upper limit")
        percent = 80
        controller.tick()
        suite.expect(controller.snapshot.command == .hold, "upper limit stops battery discharge")
        percent = 75
        controller.tick()
        suite.expect(controller.qualification?.stage == 3 && controller.snapshot.command == .charge,
                     "recharge test starts only at the lower limit")
        controller.qualification?.began = Date().addingTimeInterval(-11)
        for _ in 0..<3 { controller.tick() }
        suite.expect(store.state.chargeQualified && store.state.dischargeQualified
            && store.state.policy.enabled && controller.snapshot.command == .charge,
            "measured recharge completes qualification and retains the requested policy")
    }

    static func policyAboveLowerLimitDefersChargingTest(_ suite: TestSuite) {
        let store = MemoryBatteryStore()
        let controller = fixture(store, FakeBatteryTransport(), percent: { 89 })
        controller.probe()
        var policy = BatteryCarePolicy()
        policy.enabled = true
        suite.expect(controller.configure(policy) && controller.qualification?.stage == 1,
                     "policy above its lower limit tests hold before discharge, not charging")
        for _ in 0..<2 {
            controller.qualification?.began = Date().addingTimeInterval(-11)
            for _ in 0..<3 { controller.tick() }
        }
        suite.expect(store.state.dischargeQualified && !store.state.chargeQualified
            && controller.snapshot.command == .discharge,
            "verified discharge resumes toward the upper limit without a premature charge test")
    }

    static func qualificationFullTimeout(_ suite: TestSuite) {
        let timedOut = fixture(MemoryBatteryStore(), FakeBatteryTransport(), percent: { 100 })
        suite.expect(timedOut.beginQualification(), "full-battery timeout fixture starts")
        timedOut.qualification?.stage = 2
        timedOut.qualification?.matches = 3
        timedOut.qualification?.began = Date().addingTimeInterval(-3601)
        timedOut.tick()
        suite.expect(timedOut.qualification == nil && !timedOut.state.ownsHardware
            && timedOut.snapshot.reason == .verificationFailed,
            "full-battery test remains bounded and restores control after an hour")
    }

    static func qualificationUnplug(_ suite: TestSuite) {
        var connected = true
        let transport = FakeBatteryTransport()
        let controller = fixture(MemoryBatteryStore(), transport, adapterPresent: { connected })
        suite.expect(controller.beginQualification(), "qualification begins with physical adapter present")
        for _ in 0..<2 {
            controller.qualification?.began = Date().addingTimeInterval(-11)
            for _ in 0..<3 { controller.tick() }
        }
        controller.tick()
        suite.expect(controller.qualification?.stage == 2 && controller.snapshot.sample?.connected == true
            && controller.snapshot.sample?.externalPowerConnected == false,
                     "intentional AC cut preserves physical presence before qualification settling completes")
        connected = false
        controller.tick()
        suite.expect(controller.qualification == nil && !controller.state.chargeQualified
            && !controller.state.dischargeQualified && !controller.state.ownsHardware,
                     "real unplug aborts qualification and clears control qualification")
        suite.expect(transport.values["CHIE"] == [0] && transport.values["CHTE"] == [0, 0, 0, 0],
                     "real unplug during qualification restores both hardware controls")
    }

    static func savedPolicyStartsAndRecovers(_ suite: TestSuite) {
        let store = MemoryBatteryStore()
        let transport = FakeBatteryTransport()
        let controller = fixture(store, transport)
        controller.probe()
        var policy = BatteryCarePolicy()
        policy.enabled = true
        suite.expect(controller.configure(policy), "unqualified charge policy is accepted")
        suite.expect(store.state.policy.enabled && controller.qualification != nil,
                     "requested policy is durable while its safety test runs")
        let restarted = fixture(store, transport)
        restarted.probe()
        suite.expect(restarted.restoreHardware(disable: false), "restart first restores system charging")
        restarted.tick()
        suite.expect(restarted.state.policy.enabled && restarted.qualification != nil,
                     "restart resumes the saved request with a fresh safety test")
        for _ in 0..<4 {
            restarted.qualification?.began = Date().addingTimeInterval(-11)
            for _ in 0..<3 { restarted.tick() }
        }
        suite.expect(restarted.state.chargeQualified && restarted.state.policy.enabled,
                     "successful test automatically activates the saved policy")
        suite.expect(restarted.snapshot.command == .charge,
                     "active policy controls charging below its lower limit")
    }

    static func failedPolicyCanRetry(_ suite: TestSuite) {
        var connected = true
        let store = MemoryBatteryStore()
        let transport = FakeBatteryTransport()
        let controller = fixture(store, transport, adapterPresent: { connected })
        controller.probe()
        var policy = BatteryCarePolicy()
        policy.enabled = true
        suite.expect(controller.configure(policy), "automatic qualification starts")
        connected = false
        controller.tick()
        suite.expect(store.state.policy.enabled && !store.state.ownsHardware
            && (store.state.qualificationFailures ?? 0) == 0 && controller.snapshot.reason == .unplugged,
            "unplug interrupts the test without consuming a retry or losing the requested policy")
        controller.tick()
        suite.expect(controller.qualification == nil && controller.snapshot.reason == .unplugged,
                     "unplugged policy waits without starting another hardware test")
        connected = true
        controller.tick()
        suite.expect(controller.qualification != nil, "saved policy retries after a real reconnection")
    }

    static func failedTestsRecoverOnReplug(_ suite: TestSuite) {
        var connected = true
        let store = MemoryBatteryStore()
        store.state.policy.enabled = true
        store.state.qualificationFailures = 3
        let transport = FakeBatteryTransport()
        let controller = fixture(store, transport, adapterPresent: { connected })
        controller.probe()
        controller.tick()
        controller.tick()
        suite.expect(controller.qualification == nil && controller.state.qualificationFailures == 3,
                     "failed qualification remains bounded while the same adapter stays attached")
        connected = false
        controller.tick()
        suite.expect(controller.snapshot.reason == .unplugged && controller.state.qualificationFailures == 3,
                     "physical unplug is reported even after the retry budget was exhausted")
        connected = true
        controller.tick()
        suite.expect(controller.qualification != nil && store.state.policy.enabled
            && store.state.qualificationFailures == 0,
                     "physical reconnection restores the retry budget and tests the saved policy")
    }

    static func transientFlowReading(_ suite: TestSuite) {
        let store = MemoryBatteryStore()
        let controller = fixture(store, FakeBatteryTransport())
        controller.probe()
        controller.state.policy.enabled = true
        controller.state.dischargeQualified = true
        controller.enact(.init(command: .discharge, reason: .discharging))
        controller.lastCommandAt = Date().addingTimeInterval(-41)
        controller.snapshot.sample = controller.readSample()
        controller.snapshot.sample?.watts = 0
        controller.verifyPowerFlow()
        suite.expect(controller.state.ownsHardware && controller.flowFailureSamples == 1,
                     "one noisy sample does not stop battery control")
        controller.snapshot.sample = controller.readSample()
        controller.verifyPowerFlow()
        suite.expect(controller.flowFailureSamples == 0 && controller.state.ownsHardware,
                     "measured discharge clears the transient failure")
        controller.lastConfirmedDischargeAt = Date().addingTimeInterval(-91)
        for _ in 0..<3 {
            controller.snapshot.sample = controller.readSample()
            controller.snapshot.sample?.watts = 0
            controller.verifyPowerFlow()
        }
        suite.expect(!controller.state.ownsHardware && !controller.state.dischargeQualified
            && controller.state.policy.enabled && controller.state.qualificationFailures == 1,
            "three failed readings restore macOS and queue a policy retry")
    }

    static func disablingDuringTest(_ suite: TestSuite) {
        let store = MemoryBatteryStore()
        let transport = FakeBatteryTransport()
        let controller = fixture(store, transport)
        controller.probe()
        var policy = BatteryCarePolicy()
        policy.enabled = true
        suite.expect(controller.configure(policy), "policy begins test")
        policy.enabled = false
        suite.expect(controller.configure(policy), "switch can turn off during test")
        suite.expect(!store.state.policy.enabled && controller.qualification == nil
            && !store.state.ownsHardware && transport.values["CHIE"] == [0],
            "turning policy off cancels test and restores system control")
    }

    static func changingPolicyDuringTest(_ suite: TestSuite) {
        let store = MemoryBatteryStore()
        store.state.dischargeQualified = true
        store.state.qualifiedFingerprint = "fixture"
        let transport = FakeBatteryTransport()
        let controller = fixture(store, transport, percent: { 88 })
        controller.probe()
        var policy = BatteryCarePolicy()
        policy.enabled = true
        suite.expect(controller.configure(policy) && controller.snapshot.command == .discharge,
                     "saved 75–80 policy discharges above its upper limit")
        var temporary = policy
        temporary.lower = 88
        temporary.upper = 90
        suite.expect(controller.configure(temporary) && controller.qualification?.stage == 3,
                     "a temporary charging range starts measured charge qualification")
        suite.expect(controller.configure(policy) && controller.qualification == nil,
                     "changing the range cancels an obsolete charging test")
        suite.expect(store.state.policy == policy && controller.snapshot.command == .discharge
            && transport.values["CHIE"] == [8],
            "the original range immediately resumes discharge")
    }

    static func dischargeUnplug(_ suite: TestSuite) {
        var connected = true
        let transport = FakeBatteryTransport()
        let controller = fixture(MemoryBatteryStore(), transport, adapterPresent: { connected })
        controller.probe()
        controller.state.chargeQualified = true
        controller.state.dischargeQualified = true
        suite.expect(controller.handle(.init(kind: .discharge, target: 40)), "manual discharge starts on qualified transport")
        controller.tick()
        suite.expect(controller.state.operation?.kind == .discharge && controller.snapshot.command == .discharge,
                     "effective AC off alone does not cancel a physically connected discharge")
        connected = false
        controller.tick()
        suite.expect(controller.state.operation == nil && !controller.state.ownsHardware && transport.values["CHIE"] == [0],
                     "physical unplug cancels manual discharge and restores the adapter path")
    }

    static func badRequest(_ suite: TestSuite) {
        let controller = fixture(MemoryBatteryStore(), FakeBatteryTransport())
        let semaphore = DispatchSemaphore(value: 0)
        var response: BatteryCareResponse?
        controller.request(Data("{}".utf8)) {
            response = try? JSONDecoder().decode(BatteryCareResponse.self, from: $0)
            semaphore.signal()
        }
        suite.expect(semaphore.wait(timeout: .now() + 2) == .success, "invalid RPC replies within bound")
        suite.expect(response?.succeeded == false && response?.snapshot.reason == .invalidRequest,
                     "malformed privileged intent has no side effect")
    }

    static func partialDischargeCapability(_ suite: TestSuite) {
        let controller = fixture(MemoryBatteryStore(), FakeBatteryTransport(), percent: { 81 })
        controller.probe()
        controller.state.dischargeQualified = true
        suite.expect(!controller.handle(.init(kind: .topUp)) && controller.state.operation == nil,
                     "discharge qualification alone cannot authorize a top-up")
        suite.expect(!controller.handle(.init(kind: .calibrate)) && controller.state.operation == nil,
                     "calibration still requires verified charging and discharging")
        suite.expect(controller.handle(.init(kind: .discharge, target: 75)),
                     "verified discharge remains available while charging waits for the lower limit")
        suite.expect(controller.snapshot.command == .discharge && controller.state.operation?.target == 75,
                     "partial capability uses the actual controller to discharge to the selected target")
        controller.state.operation?.paused = true
        suite.expect(controller.handle(.init(kind: .resume)) && controller.state.operation?.paused == false,
                     "a paused manual discharge resumes without requiring an unrelated charge qualification")
    }
}

final class MemoryBatteryStore: BatteryStateStore {
    var state = BatteryCareState()
    var failReads = false
    var failWrites = false
    func load() throws -> BatteryCareState {
        if failReads { throw BatteryJournal.Failure.corrupt }
        return state
    }
    func save(_ state: BatteryCareState) throws {
        if failWrites { throw BatteryJournal.Failure.write }
        self.state = state
    }
}

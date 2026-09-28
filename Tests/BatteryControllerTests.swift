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
        qualificationUnplug(suite)
        dischargeUnplug(suite)
        badRequest(suite)
    }

    static func fixture(_ store: MemoryBatteryStore, _ transport: FakeBatteryTransport,
                        competitors: @escaping () -> [String] = { [] },
                        adapterPresent: @escaping () -> Bool = { true }) -> BatteryController {
        var readingNumber = 0
        let time = Date()
        return BatteryController(journal: store, automaticallyStart: false,
            makeHardware: { try BatteryHardware(transport: transport) }, readSample: {
                let discharge = transport.values["CHIE"] == [8]
                let charge = !discharge && transport.values["CHTE"] == [0, 0, 0, 0]
                readingNumber += 1
                let connected = adapterPresent()
                return BatterySensor.decode(["CurrentCapacity": 60, "MaxCapacity": 100, "Temperature": 3032,
                    "AppleRawExternalConnected": connected, "ExternalConnected": connected && !discharge,
                    "IsCharging": connected && charge, "Voltage": 10000,
                    "Amperage": !connected || discharge ? -1000 : charge ? 1000 : 0],
                    at: time.addingTimeInterval(Double(readingNumber) / 1000))
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
        suite.expect(!controller.state.policy.enabled && controller.snapshot.reason == .conflict,
                     "controller drift stops control instead of fighting it")
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

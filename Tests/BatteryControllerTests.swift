// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import Foundation

enum BatteryControllerTests {
    static func run(_ suite: TestSuite) {
        restoreRetry(suite)
        journalFailure(suite)
        drift(suite)
        restart(suite)
        qualification(suite)
        badRequest(suite)
    }

    static func fixture(_ store: MemoryBatteryStore, _ transport: FakeBatteryTransport,
                        competitors: @escaping () -> [String] = { [] }) -> BatteryController {
        var readingNumber = 0
        let time = Date()
        return BatteryController(journal: store, automaticallyStart: false,
            makeHardware: { try BatteryHardware(transport: transport) }, readSample: {
                let discharge = transport.values["CHIE"] == [8]
                let charge = !discharge && transport.values["CHTE"] == [0, 0, 0, 0]
                readingNumber += 1
                return .init(at: time.addingTimeInterval(Double(readingNumber) / 1000), percent: 60, temperature: 30, connected: true,
                             charging: charge, watts: discharge ? -10 : charge ? 10 : 0)
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

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import Foundation

enum BatteryNativeControllerTests {
    static func run(_ suite: TestSuite) {
        do {
            try backendQualification(suite)
            try savedPolicy(suite)
            try qualification(suite)
            try restart(suite)
        } catch { suite.expect(false, "native controller checks failed: \(error)") }
    }

    private static func backendQualification(_ suite: TestSuite) throws {
        let fixture = NativeControllerFixture()
        fixture.store.state.chargeQualified = true
        fixture.store.state.dischargeQualified = true
        fixture.store.state.qualifiedFingerprint = "fixture"
        let controller = fixture.controller()
        controller.probe()
        suite.expect(!controller.state.chargeQualified && !controller.state.dischargeQualified,
                     "a legacy qualification cannot authorize the native backend")
        suite.expect(controller.snapshot.fingerprint == "fixture · native-owned-policy:v1",
                     "native qualification is bound to the backend as well as firmware and macOS")
        let writes = fixture.io.writes
        suite.expect(!controller.canControl(discharge: true) && fixture.io.writes == writes,
                     "recognizing the native policy schema does not authorize battery control")
    }

    private static func savedPolicy(_ suite: TestSuite) throws {
        let fixture = NativeControllerFixture()
        fixture.qualifiedPolicy()
        let controller = fixture.controller()
        controller.probe(); controller.tick()
        suite.expect(fixture.store.state.nativeLease?.target == 80 && controller.snapshot.command == .charge,
                     "a qualified policy charges below 75 with its own 80 ceiling")
        var policy = controller.state.policy; policy.upper = 85
        suite.expect(controller.configure(policy) && fixture.store.state.nativeLease?.target == 85,
                     "editing the upper limit changes the existing native charge lease")
        fixture.percent = 85; controller.tick()
        suite.expect(fixture.store.state.nativeLease?.target == 1 && controller.snapshot.command == .hold,
                     "reaching the upper limit enters no-drain hold")
        let reloads = fixture.io.reloads
        fixture.percent = 82; controller.tick()
        suite.expect(fixture.io.reloads == reloads && controller.snapshot.command == .hold,
                     "the lower threshold prevents a small drop from restarting charging")
        fixture.percent = 74; controller.tick()
        suite.expect(controller.snapshot.command == .charge && fixture.store.state.nativeLease?.target == 85,
                     "charging resumes only at the saved lower threshold")
        policy.enabled = false
        suite.expect(controller.configure(policy) && fixture.store.state.nativeLease == nil,
                     "disabling Aster removes its own lease without changing macOS's manual setting")
    }

    private static func qualification(_ suite: TestSuite) throws {
        let fixture = NativeControllerFixture()
        fixture.store.state.policy.enabled = true
        fixture.percent = 88
        let controller = fixture.controller()
        suite.expect(controller.beginQualification(), "native backend starts a measured bounded test")
        advance(controller)
        suite.expect(controller.qualification?.stage == 2 && fixture.store.state.nativeLease?.drain == true,
                     "verified holding advances to discharge measurement")
        advance(controller)
        suite.expect(controller.state.dischargeQualified && !controller.state.chargeQualified,
                     "above the charging range only measured discharge is qualified")
        suite.expect(fixture.store.state.nativeLease?.target == 80 && fixture.store.state.nativeLease?.drain == true,
                     "qualification hands discharge directly to the saved upper limit")
        fixture.percent = 74; controller.tick()
        suite.expect(controller.qualification?.stage == 3 && fixture.store.state.nativeLease?.target == 80,
                     "deferred charging test stays bounded by Aster's ceiling")
        let reloads = fixture.io.reloads
        advance(controller)
        suite.expect(controller.state.chargeQualified && fixture.io.reloads == reloads,
                     "charging qualification finishes without a gap that removes protection")
    }

    private static func restart(_ suite: TestSuite) throws {
        let fixture = NativeControllerFixture()
        fixture.qualifiedPolicy()
        let original = fixture.controller()
        original.probe(); original.tick()
        let token = fixture.store.state.nativeLease!.token
        fixture.io.live = []; fixture.owner = 3456
        let replacement = fixture.controller()
        replacement.probe()
        suite.expect(replacement.state.chargeQualified && replacement.resumeNativeLeaseAtStart(),
                     "same backend restart retains its measured qualification and durable policy")
        replacement.tick()
        suite.expect(replacement.state.nativeLease?.token == token && replacement.state.nativeLease?.owner == 3456,
                     "first replacement tick reclaims the saved rule without removing protection first")
    }

    private static func advance(_ controller: BatteryController) {
        controller.qualification?.began = Date().addingTimeInterval(-11)
        for _ in 0..<3 { controller.tick() }
    }
}

private final class NativeControllerFixture {
    let store = MemoryBatteryStore()
    let io = NativeBatteryIO()
    var percent = 60, owner = 2345
    private var sampleNumber = 0

    func qualifiedPolicy() {
        store.state.policy.enabled = true
        store.state.qualifiedFingerprint = "fixture · native-owned-policy:v1"
        store.state.chargeQualified = true; store.state.dischargeQualified = true
    }

    func controller() -> BatteryController {
        var controller: BatteryController!
        controller = BatteryController(journal: store, automaticallyStart: false,
            makeHardware: { [self] in
                try BatteryNativeHardware(io: io, owner: owner, load: { controller.state.nativeLease }, save: { value in
                    controller.state.nativeLease = value
                    guard controller.save() else { throw BatteryHardwareError.unavailable }
                })
            }, readSample: { [self] in sample() }, readCompetitors: { [] }, fingerprint: "fixture")
        io.journalReady = { [self] in store.state.nativeLease != nil }
        return controller
    }

    private func sample() -> BatterySample {
        sampleNumber += 1
        let target = (io.live.first?["chargeSocLimitSoc"] as? Int) ?? 100
        let draining = (io.live.first?["chargeSocLimitDrain"] as? Int) == 1
        let charging = !draining && target > percent
        return .init(at: Date().addingTimeInterval(Double(sampleNumber) / 100_000), percent: percent,
            temperature: 30, connected: true, charging: charging, watts: draining ? -10 : charging ? 10 : 0)
    }
}

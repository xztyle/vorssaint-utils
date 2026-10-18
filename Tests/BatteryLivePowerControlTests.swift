// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import Foundation

/// The actual property decoder and controller run against inert hardware.
enum BatteryLivePowerControlTests {
    static func run(_ suite: TestSuite) {
        sensorTransitions(suite)
        upperLimitWithLaggingRegistry(suite)
        realHoldFailure(suite)
    }

    private static func sensorTransitions(_ suite: TestSuite) {
        let stale = properties(charging: true, amps: 4685)
        let paused = BatterySensor.decode(stale, at: Date(), liveWatts: 0)
        suite.expect(paused.watts == 0 && paused.charging == false,
                     "a fresh zero clears both the minute-old current and charging flag")
        let draining = BatterySensor.decode(stale, at: Date(), liveWatts: -24.866)
        suite.expect(draining.watts == -24.866 && draining.charging == false,
                     "live discharge cannot retain a stale charging flag")
        let charging = BatterySensor.decode(properties(charging: false, amps: 0), at: Date(), liveWatts: 56.316)
        suite.expect(charging.watts == 56.316 && charging.charging == true,
                     "real resumed charging is not hidden by a lagging paused flag")
        for invalid: Double? in [nil, .nan, .infinity, 1000] {
            let fallback = BatterySensor.decode(stale, at: Date(), liveWatts: invalid)
            suite.expect(fallback.charging == true && abs((fallback.watts ?? 0) - 56.22) < 0.001,
                         "unsupported live power preserves the original registry fallback")
        }
        suite.expect(!BatterySensor.decode([:], at: Date(), liveWatts: 0).isFresh(at: Date()),
                     "live power cannot invent missing temperature, charge or physical adapter presence")
    }

    private static func upperLimitWithLaggingRegistry(_ suite: TestSuite) {
        let fixture = Fixture(registryCharging: true, registryAmps: 4685, liveWatts: 56.22)
        fixture.percent = 79
        fixture.controller.tick()
        suite.expect(fixture.controller.snapshot.command == .charge, "an existing recharge continues below the upper limit")
        fixture.percent = 80; fixture.liveWatts = 0
        fixture.controller.tick()
        suite.expect(fixture.controller.snapshot.command == .hold, "the upper limit pauses charging")
        fixture.controller.lastCommandAt = .distantPast
        for _ in 0..<15 { fixture.controller.tick() }
        suite.expect(fixture.controller.snapshot.command == .hold && fixture.controller.snapshot.reason == .holding,
                     "the captured stale-current sequence never restores system charging after a successful pause")
        suite.expect(fixture.controller.state.chargeQualified && fixture.controller.state.dischargeQualified,
                     "a working pause does not discard verified capabilities or restart discharge tests")
        suite.expect(fixture.controller.state.policy.enabled && fixture.controller.qualification == nil,
                     "the saved limit stays enabled without repeated qualification")
    }

    private static func realHoldFailure(_ suite: TestSuite) {
        let fixture = Fixture(registryCharging: false, registryAmps: 0, liveWatts: 56.316)
        fixture.controller.tick()
        fixture.controller.lastCommandAt = .distantPast
        for _ in 0..<3 { fixture.controller.tick() }
        suite.expect(fixture.controller.snapshot.reason == .verificationFailed,
                     "a genuine live charging flow after hold still fails verification")
        suite.expect(fixture.controller.state.policy.enabled && !fixture.controller.state.chargeQualified,
                     "a real failure preserves intent but invalidates the hardware capability")
    }

    private static func properties(charging: Bool, amps: Int) -> [String: Any] {
        ["CurrentCapacity": 80, "MaxCapacity": 100, "Temperature": 3067,
         "AdapterDetails": ["Watts": 140], "ExternalConnected": true,
         "IsCharging": charging, "Voltage": 12000, "Amperage": amps]
    }

    private final class Fixture {
        var percent = 80
        var liveWatts: Double
        var reading = 0
        let registryCharging: Bool
        let registryAmps: Int
        private let transport = FakeBatteryTransport()
        private let store = MemoryBatteryStore()
        lazy var controller: BatteryController = makeController()

        init(registryCharging: Bool, registryAmps: Int, liveWatts: Double) {
            self.registryCharging = registryCharging; self.registryAmps = registryAmps; self.liveWatts = liveWatts
            store.state.policy.enabled = true; store.state.policy.automaticDischarge = false
            store.state.chargeQualified = true; store.state.dischargeQualified = true
            store.state.qualifiedFingerprint = "fixture"; store.state.chargingLatch = true
        }

        private func makeController() -> BatteryController {
            let controller = BatteryController(journal: store, automaticallyStart: false,
                makeHardware: { try BatteryHardware(transport: self.transport) },
                readSample: { self.sample() }, readCompetitors: { [] }, fingerprint: "fixture")
            controller.probe()
            return controller
        }

        private func sample() -> BatterySample {
            reading += 1
            var properties = BatteryLivePowerControlTests.properties(charging: registryCharging, amps: registryAmps)
            properties["CurrentCapacity"] = percent
            return BatterySensor.decode(properties, at: Date().addingTimeInterval(Double(reading) / 1000),
                                        liveWatts: liveWatts)
        }
    }
}

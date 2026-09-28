// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import Foundation

enum BatteryRegistrationRepairTests {
    static func run(_ suite: TestSuite) {
        for failure in [false, true] {
            let fixture = Fixture()
            fixture.run()
            suite.expect(fixture.removals == 1 && fixture.result == nil,
                         "registration-only repair waits for asynchronous service removal")
            fixture.finished?(failure ? NSError(domain: "fixture", code: 1) : nil)
            suite.expect(fixture.result == (failure ? .unregisterFailed : .unregistered),
                         "registration repair reports actual unregister completion")
            suite.expect(fixture.transport.writeCount == 0,
                         "registration repair only reads hardware; it never restores or changes keys")
        }
        blockedPrerequisites(suite)
        blockedHardware(suite)
    }

    private static func blockedPrerequisites(_ suite: TestSuite) {
        let enabled = Fixture()
        enabled.run(enabled: true)
        suite.expect(enabled.result == .featureEnabled && enabled.removals == 0 && enabled.reads == 0,
                     "enabled Battery care prevents maintenance removal before hardware access")
        let unsigned = Fixture()
        unsigned.run(signed: false)
        suite.expect(unsigned.result == .signingUnavailable && unsigned.removals == 0 && unsigned.reads == 0,
                     "untrusted signing prevents maintenance removal before hardware access")
    }

    private static func blockedHardware(_ suite: TestSuite) {
        for state in ["inhibit", "cut", "conflict", "unknown", "shape"] {
            let fixture = Fixture()
            if state == "inhibit" || state == "conflict" { fixture.transport.values["CHTE"] = [1, 0, 0, 0] }
            if state == "cut" || state == "conflict" { fixture.transport.values["CHIE"] = [8] }
            if state == "unknown" { fixture.transport.values["CHIE"] = [7] }
            fixture.transport.wrongShape = state == "shape"
            fixture.run()
            suite.expect(fixture.result == .hardwareNotRestored && fixture.removals == 0
                && fixture.transport.writeCount == 0,
                         "\(state) hardware blocks registration repair without writes or removal")
        }
    }

    final class Fixture {
        let transport = FakeBatteryTransport()
        var removals = 0
        var reads = 0
        var result: BatteryRegistrationRepair.Result?
        var finished: ((Error?) -> Void)?

        func run(enabled: Bool = false, signed: Bool = true) {
            BatteryRegistrationRepair.unregister(featureEnabled: enabled, hasStableSigning: signed,
                readHardware: {
                    self.reads += 1
                    return try? BatteryHardware(transport: self.transport).readState()
                }, removeService: { completion in
                    self.removals += 1
                    self.finished = completion
                }, completion: { self.result = $0 })
        }
    }
}

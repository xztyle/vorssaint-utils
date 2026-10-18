// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import Foundation

enum BatteryCompatibilityTests {
    static func run(_ suite: TestSuite) {
        var snapshot = BatteryCareSnapshot()
        snapshot.reason = .unavailable
        for diagnostic in ["controller(132)", "transport(-536870207)"] {
            snapshot.diagnostic = diagnostic
            suite.expect(BatteryControlCompatibility.isRestricted(snapshot),
                         "removed or entitlement-gated control cannot look like a waiting test")
        }
        snapshot.reason = .recovery
        suite.expect(!BatteryControlCompatibility.isRestricted(snapshot), "pending restoration retains priority")
        snapshot.reason = .unavailable; snapshot.chargeCandidate = true
        suite.expect(!BatteryControlCompatibility.isRestricted(snapshot), "available hardware retains qualification controls")
        snapshot.chargeCandidate = false; snapshot.qualificationStep = 1
        suite.expect(!BatteryControlCompatibility.isRestricted(snapshot), "an active test retains its progress")
        snapshot.qualificationStep = nil; snapshot.diagnostic = "shape"
        suite.expect(!BatteryControlCompatibility.isRestricted(snapshot), "unknown failures are not misreported as system denial")
        temperature(suite)
    }

    private static func temperature(_ suite: TestSuite) {
        suite.expectClose(BatteryTemperatureSampler.validated([33.4, 35.1]) ?? .nan, 35.1,
                          "the hotter measured battery cell is used")
        suite.expectClose(BatteryTemperatureSampler.validated([.nan, -1, 33.4, 66]) ?? .nan, 33.4,
                          "invalid cell readings do not hide a valid temperature")
        suite.expect(BatteryTemperatureSampler.validated([.nan, .infinity, -.infinity, -1, 66]) == nil,
                     "missing temperature stays unknown")
        suite.expect(BatteryTemperatureSampler.validated([]) == nil, "no sensor does not invent a temperature")
        suite.expect(BatteryTemperatureSampler(smc: nil).sample() == nil, "unavailable SMC is handled")
    }
}

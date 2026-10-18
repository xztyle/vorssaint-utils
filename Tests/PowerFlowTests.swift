// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import Foundation

enum PowerFlowTests {
    static func run(_ suite: TestSuite) {
        charging(suite)
        paused(suite)
        discharging(suite)
        assisting(suite)
        unavailable(suite)
        freshness(suite)
        translations(suite)
    }

    private static func model(_ adapter: Double?, _ battery: Double?, _ system: Double?, connected: Bool = true) -> PowerFlowModel {
        .make(adapter: adapter, battery: battery, system: system, connected: connected, sampledAt: Date(timeIntervalSince1970: 100))
    }

    private static func charging(_ suite: TestSuite) {
        let result = model(60, 20, 28)
        suite.expect(result.state == .charging, "positive battery watts show charging")
        suite.expect(result.destinations == [.init(role: .mac, watts: 40), .init(role: .batteryCharge, watts: 20)],
            "charging splits real source input between Mac and battery")
        suite.expect(result.calculatedMac, "Mac flow is explicitly calculated, not called the independent system measurement")
        balanced(result, suite: suite)
        let full = model(20, 20, 1)
        suite.expect(full.destinations.first?.watts == 0, "all measured input can go to the battery without a negative Mac flow")
        balanced(full, suite: suite)
    }

    private static func paused(_ suite: TestSuite) {
        let result = model(25, 0, 39)
        suite.expect(result.state == .paused, "zero battery watts show paused charging")
        suite.expect(result.destinations == [.init(role: .mac, watts: 25)], "paused diagram does not force a different system sensor to balance")
        suite.expect(result.links.count == 1, "paused battery has no fake charging branch")
        balanced(result, suite: suite)
        suite.expect(model(25, -0.2, 39).state == .paused, "small negative battery noise does not invent a discharge source")
        suite.expect(model(25, 0.2, 39).state == .paused, "small positive battery noise does not invent a charging branch")
    }

    private static func discharging(_ suite: TestSuite) {
        let result = model(90, -18, 21, connected: false)
        suite.expect(result.state == .discharging, "unplugged battery supply shows discharge")
        suite.expect(result.sources == [.init(role: .batterySource, watts: 18)], "old adapter telemetry cannot power an unplugged diagram")
        suite.expect(result.destinations == [.init(role: .mac, watts: 18)], "battery output supplies the Mac")
        balanced(result, suite: suite)
        let emptyAdapter = model(0, -18, 21)
        suite.expect(emptyAdapter.state == .discharging, "a physically connected adapter drawing zero does not claim battery assist")
        balanced(emptyAdapter, suite: suite)
    }

    private static func assisting(_ suite: TestSuite) {
        let result = model(10, -15, 23)
        suite.expect(result.state == .assisting, "negative battery watts with live adapter input shows dual supply")
        suite.expect(result.sources.count == 2, "battery assist displays both measured sources")
        suite.expect(result.destinations == [.init(role: .mac, watts: 25)], "adapter and battery supply add together")
        balanced(result, suite: suite)
    }

    private static func unavailable(_ suite: TestSuite) {
        let missing = model(nil, 15, 20)
        suite.expect(missing.sources.first?.watts == nil, "missing adapter reading remains unknown")
        suite.expect(!missing.calculatedMac && missing.destinations.first?.watts == 20, "unknown source uses the separately measured system value")
        suite.expect(missing.links.allSatisfy { $0.watts == nil }, "unknown adapter cannot create measured flow amounts")
        let absentBattery = model(50, nil, 20)
        suite.expect(!absentBattery.calculatedMac && absentBattery.state == .unavailable, "missing battery flow is not assumed to be zero")
        suite.expect(absentBattery.links.first?.watts == nil, "missing battery data cannot label all input as Mac consumption")
        let mismatch = model(10, 40, 20)
        suite.expect(mismatch.readingsSettling, "battery charge exceeding input is marked as unsettled")
        suite.expect(mismatch.links.allSatisfy { $0.watts == nil }, "mismatched readings do not render a false balanced Sankey")
        suite.expect(mismatch.destinations.first?.watts == 20 && !mismatch.calculatedMac, "mismatch preserves separate system measurement")
        let invalid = model(.infinity, .nan, -5)
        suite.expect(invalid.state == .unavailable && invalid.sources.first?.watts == nil,
            "nonfinite and negative telemetry cannot appear as real power")
    }

    private static func balanced(_ result: PowerFlowModel, suite: TestSuite) {
        let supply = result.sources.compactMap(\.watts).reduce(0, +)
        let use = result.destinations.compactMap(\.watts).reduce(0, +)
        let links = result.links.compactMap(\.watts).reduce(0, +)
        suite.expectClose(supply, use, "known flow conserves total source power")
        suite.expectClose(supply, links, "known link amounts account for source power")
    }

    private static func freshness(_ suite: TestSuite) {
        let result = model(25, 0, 20)
        suite.expect(result.isFresh(at: Date(timeIntervalSince1970: 105), interval: 2), "current sample is live")
        suite.expect(!result.isFresh(at: Date(timeIntervalSince1970: 108), interval: 2), "stopped two-second sampler loses its live status")
        suite.expect(result.isFresh(at: Date(timeIntervalSince1970: 114), interval: 5), "five-second preference uses its actual sampling cadence")
        suite.expect(!result.isFresh(at: Date(timeIntervalSince1970: 96), interval: 2), "future sample after clock change does not claim live data")
    }

    private static func translations(_ suite: TestSuite) {
        for language in AppLanguage.allCases {
            let strings = FeatureStrings.powerFlow(language)
            suite.expect(strings.values.count == PowerFlowText.allCases.count, "complete power-flow strings for \(language.rawValue)")
            suite.expect(strings.values.allSatisfy { !$0.isEmpty }, "nonempty power-flow strings for \(language.rawValue)")
        }
    }
}

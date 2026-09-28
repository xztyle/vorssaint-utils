// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import Foundation

enum BatteryCareTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func run(_ suite: TestSuite) {
        ranges(suite)
        thermal(suite)
        discharge(suite)
        operations(suite)
        calibration(suite)
        schedules(suite)
        scheduleDST(suite)
        protocolValidation(suite)
        replyCompletion(suite)
        hardware(suite)
        sensors(suite)
        adapterPresence(suite)
        BatteryRegistrationRepairTests.run(suite)
        BatteryControllerTests.run(suite)
        #if !BATTERY_STANDALONE
        localizationAndBackup(suite)
        BatteryHelperUpgradeTests.run(suite)
        #endif
    }

    static func sample(_ percent: Int, temperature: Double = 30, connected: Bool = true,
                       charging: Bool = false, at: Date = now) -> BatterySample {
        .init(at: at, percent: percent, temperature: temperature, connected: connected,
              charging: charging, watts: charging ? 10 : -1)
    }

    static func state() -> BatteryCareState {
        var state = BatteryCareState()
        state.policy.enabled = true
        return state
    }

    static func ranges(_ suite: TestSuite) {
        var state = state()
        suite.expect(BatteryPolicy.decide(state: &state, sample: sample(77), now: now).command == .hold,
                     "restart inside range holds without small top-up")
        suite.expect(BatteryPolicy.decide(state: &state, sample: sample(75), now: now).command == .charge,
                     "lower bound starts charging")
        suite.expect(BatteryPolicy.decide(state: &state, sample: sample(77), now: now).command == .charge,
                     "charge latch continues through range")
        let encoded = try! JSONEncoder().encode(state)
        state = try! JSONDecoder().decode(BatteryCareState.self, from: encoded)
        suite.expect(BatteryPolicy.decide(state: &state, sample: sample(79), now: now).command == .charge,
                     "restart preserves charge latch")
        suite.expect(BatteryPolicy.decide(state: &state, sample: sample(80), now: now).command == .hold,
                     "upper bound stops charging")
        suite.expect(BatteryPolicy.decide(state: &state, sample: sample(69), now: now, sleeping: true).command == .hold,
                     "sleep inhibits charging below limit")
        state.scheduledPause = true
        suite.expect(BatteryPolicy.decide(state: &state, sample: sample(69), now: now).command == .system,
                     "scheduled pause releases control")
    }

    static func thermal(_ suite: TestSuite) {
        var state = state()
        suite.expect(BatteryPolicy.decide(state: &state, sample: sample(50, temperature: 40), now: now).command == .hold,
                     "temperature cutoff immediately stops charging")
        suite.expect(BatteryPolicy.decide(state: &state, sample: sample(50, temperature: 37), now: now).command == .hold,
                     "heat hysteresis does not resume above lower threshold")
        _ = BatteryPolicy.decide(state: &state, sample: sample(50, temperature: 35), now: now)
        let later = now.addingTimeInterval(60)
        suite.expect(BatteryPolicy.decide(state: &state, sample: sample(50, temperature: 35, at: later), now: later).command == .charge,
                     "charging resumes after stable cool minute")
        suite.expect(BatteryPolicy.decide(state: &state, sample: sample(50), now: later).reason == .staleSensor,
                     "stale reading cannot permit a new charge")
        var missing = sample(50)
        missing.temperature = nil
        suite.expect(BatteryPolicy.decide(state: &state, sample: missing, now: now).command == .hold,
                     "missing battery temperature fails safely")
        suite.expect(BatteryPolicy.decide(state: &state, sample: sample(50, temperature: .nan), now: now).reason == .staleSensor,
                     "nonfinite temperature rejected")
    }

    static func discharge(_ suite: TestSuite) {
        var state = state()
        state.policy.automaticDischarge = true
        suite.expect(BatteryPolicy.decide(state: &state, sample: sample(85), now: now).command == .discharge,
                     "auto discharge above upper limit")
        suite.expect(BatteryPolicy.decide(state: &state, sample: sample(80), now: now).command == .hold,
                     "auto discharge stops at upper bound")
        suite.expect(BatteryPolicy.begin(.discharge, target: 30, state: &state, now: now), "manual discharge starts")
        suite.expect(BatteryPolicy.decide(state: &state, sample: sample(50), now: now).command == .discharge,
                     "manual discharge follows target")
        _ = BatteryPolicy.decide(state: &state, sample: sample(30), now: now)
        suite.expect(state.operation == nil && state.policy.automaticDischarge, "manual completion restores policy")
        _ = BatteryPolicy.begin(.discharge, target: 10, state: &state, now: now)
        _ = BatteryPolicy.decide(state: &state, sample: sample(50), now: now)
        let later = now.addingTimeInterval(6 * 3600)
        suite.expect(BatteryPolicy.decide(state: &state, sample: sample(40, at: later), now: later).reason == .timeout,
                     "bounded discharge times out safely")
        suite.expect(!state.policy.automaticDischarge, "timeout prevents automatic immediate restart")
    }

    static func operations(_ suite: TestSuite) {
        var state = state()
        let saved = state.policy
        _ = BatteryPolicy.begin(.topUp, state: &state, now: now)
        suite.expect(!BatteryPolicy.begin(.calibration, state: &state, now: now), "exclusive operation cannot overlap")
        suite.expect(BatteryPolicy.decide(state: &state, sample: sample(99), now: now).command == .charge,
                     "top-up bypasses normal upper bound")
        suite.expect(BatteryPolicy.decide(state: &state, sample: sample(100), now: now).command == .charge,
                     "top-up remains available until unplugged")
        _ = BatteryPolicy.decide(state: &state, sample: sample(99, connected: false), now: now)
        suite.expect(state.operation == nil && state.policy == saved, "first unplug restores exact top-up policy")
        _ = BatteryPolicy.begin(.calibration, state: &state, now: now)
        _ = BatteryPolicy.decide(state: &state, sample: sample(75), now: now, sleeping: true)
        suite.expect(state.operation?.paused == true, "sleep pauses calibration for deliberate resume")
        state.cancelOperation()
        suite.expect(state.policy == saved && state.operation == nil, "cancel restores saved policy")
    }

    static func calibration(_ suite: TestSuite) {
        var state = state()
        _ = BatteryPolicy.begin(.calibration, state: &state, now: now)
        suite.expect(BatteryPolicy.decide(state: &state, sample: sample(99), now: now).command == .charge, "first full charge")
        suite.expect(BatteryPolicy.decide(state: &state, sample: sample(100), now: now).command == .discharge,
                     "calibration reaches discharge only at full and no active charging")
        suite.expect(BatteryPolicy.decide(state: &state, sample: sample(10), now: now).command == .charge,
                     "ten-percent floor reconnects adapter")
        _ = BatteryPolicy.decide(state: &state, sample: sample(100), now: now)
        suite.expect(state.operation?.phase == .hold, "second full charge enters hold")
        for tick in 1...360 {
            let time = now.addingTimeInterval(Double(tick * 10))
            _ = BatteryPolicy.decide(state: &state, sample: sample(100, at: time), now: time)
        }
        suite.expect(state.operation == nil && state.policy.upper == 80, "one hour of measured full hold restores policy")
        _ = BatteryPolicy.begin(.calibration, state: &state, now: now)
        state.operation?.phase = .hold
        state.lastTick = now
        let future = now.addingTimeInterval(3600)
        _ = BatteryPolicy.decide(state: &state, sample: sample(100, at: future), now: future)
        suite.expect(state.operation?.holdSeconds == 0, "sleep or wall-clock jump does not count as measured hold")
    }

    static func schedules(_ suite: TestSuite) {
        var schedule = BatterySchedule(start: now.addingTimeInterval(-120), repetition: .once)
        suite.expect(BatteryScheduler.due([schedule], since: now.addingTimeInterval(-300), now: now, fired: []).isEmpty,
                     "missed tasks skip by default")
        schedule.runMissed = true
        let due = BatteryScheduler.due([schedule], since: now.addingTimeInterval(-300), now: now, fired: [])
        suite.expect(due.count == 1, "next opportunity runs a fresh missed task")
        suite.expect(BatteryScheduler.due([schedule], since: now.addingTimeInterval(-300), now: now,
                                         fired: Set(due.map(\.key))).isEmpty, "persisted occurrence cannot run twice")
        suite.expect(BatteryScheduler.due([schedule], since: now.addingTimeInterval(-300),
            now: now.addingTimeInterval(21601), fired: []).isEmpty, "six-hour freshness bound prevents stale discharge")
        var duplicate = schedule
        duplicate.id = UUID()
        let both = BatteryScheduler.due([schedule, duplicate], since: now.addingTimeInterval(-300), now: now, fired: [])
        suite.expect(both.count == 2 && both[0].schedule.id.uuidString < both[1].schedule.id.uuidString,
                     "same-time schedules have deterministic ordering")
    }

    static func scheduleDST(_ suite: TestSuite) {
        let formatter = ISO8601DateFormatter()
        var schedule = BatterySchedule(start: formatter.date(from: "2026-03-07T07:30:00Z")!,
                                        timeZone: "America/New_York", repetition: .daily)
        let spring = BatteryScheduler.latestOccurrence(schedule, now: formatter.date(from: "2026-03-08T08:00:00Z")!)
        suite.expect(spring == formatter.date(from: "2026-03-08T07:00:00Z"), "DST gap uses next valid local time")
        schedule.start = formatter.date(from: "2026-10-31T05:30:00Z")!
        let fall = BatteryScheduler.latestOccurrence(schedule, now: formatter.date(from: "2026-11-01T07:00:00Z")!)
        suite.expect(fall == formatter.date(from: "2026-11-01T05:30:00Z"), "DST repeat chooses first occurrence only")
        schedule.repetition = .biweekly
        let next = BatteryScheduler.latestOccurrence(schedule, now: formatter.date(from: "2026-11-14T08:00:00Z")!)
        suite.expect(next == formatter.date(from: "2026-11-14T06:30:00Z"), "biweekly stays on civil days across DST")
    }

    static func protocolValidation(_ suite: TestSuite) {
        suite.expect(BatteryCareIPC.decodeRequest(Data(repeating: 32, count: 65537)) == nil, "oversized IPC rejected")
        suite.expect(BatteryCareIPC.decodeRequest(Data("{}".utf8)) == nil, "malformed IPC rejected")
        for target in [-1, 0, 9, 100, 10000] {
            let request = BatteryCareRequest(kind: .discharge, target: target)
            suite.expect(!request.isValid, "invalid discharge target rejected: \(target)")
        }
        var policy = BatteryCarePolicy()
        policy.lower = policy.upper
        suite.expect(!policy.isValid, "inverted range rejected")
        policy = BatteryCarePolicy()
        policy.heatResume = policy.heatCutoff
        suite.expect(!policy.isValid, "heat thresholds need hysteresis")
        var state = BatteryCareState()
        state.version = 999
        suite.expect(!state.isValid, "unsupported journal schema rejected")
    }

    static func replyCompletion(_ suite: TestSuite) {
        var gate = BatteryReplyGate()
        let request = gate.begin()
        suite.expect(gate.consume(request), "XPC failure completes the active request")
        suite.expect(!gate.consume(request), "timeout after error cannot complete twice")
        let retry = gate.begin()
        suite.expect(!gate.consume(request), "late old reply cannot consume the retry")
        suite.expect(gate.consume(retry), "retry remains available after the old failure")
    }

    static func hardware(_ suite: TestSuite) {
        let fake = FakeBatteryTransport()
        let hardware = try! BatteryHardware(transport: fake)
        try! hardware.apply(.hold)
        suite.expect(fake.values["CHTE"] == [1, 0, 0, 0], "CHTE uses observed little-endian bytes")
        try! hardware.apply(.discharge)
        suite.expect(fake.values["CHTE"] == [0, 0, 0, 0] && fake.values["CHIE"] == [8], "discharge clears inhibit first")
        try! hardware.apply(.system)
        suite.expect(fake.values["CHIE"] == [0] && fake.values["CHTE"] == [0, 0, 0, 0], "return clears both controls")
        fake.values["CHIE"] = [8]
        suite.expect((try? hardware.verifyOwnership()) == nil, "controller drift is detected")
        fake.denyWrites = true
        suite.expect((try? hardware.apply(.system)) == nil, "denied restoration is not reported successful")
        fake.denyWrites = false
        fake.ignoreWrites = true
        suite.expect((try? hardware.apply(.system)) == nil, "write success without readback change is rejected")
        fake.ignoreWrites = false
        fake.wrongShape = true
        suite.expect((try? BatteryHardware(transport: fake)) == nil, "wrong hardware shape is unavailable")
    }

    static func sensors(_ suite: TestSuite) {
        let sample = BatterySensor.decode(["CurrentCapacity": 80, "MaxCapacity": 100,
            "Temperature": 3078, "ExternalConnected": true, "IsCharging": false,
            "Voltage": 12000, "Amperage": UInt32.max - 999], at: now)
        suite.expect(abs((sample.temperature ?? 0) - 34.65) < 0.01, "battery decikelvin conversion")
        suite.expect(sample.watts == -12, "unsigned IORegistry current becomes signed discharge")
        suite.expect(sample.isFresh(at: now), "complete measured sample accepted")
        suite.expect(!BatterySensor.decode([:], at: now).isFresh(at: now), "missing properties never imply safe state")
        var missingCurrent = sample
        missingCurrent.watts = nil
        suite.expect(!missingCurrent.isFresh(at: now), "missing current stops discharge immediately")
    }

    static func adapterPresence(_ suite: TestSuite) {
        var properties: [String: Any] = ["CurrentCapacity": 80, "MaxCapacity": 100,
            "Temperature": 3078, "ExternalConnected": false, "IsCharging": false,
            "Voltage": 12000, "Amperage": -1000, "AppleRawExternalConnected": true]
        let cut = BatterySensor.decode(properties, at: now)
        suite.expect(cut.connected == true && cut.externalPowerConnected == false && cut.isFresh(at: now),
                     "physical attachment remains distinct from intentionally cut effective AC")
        properties["AppleRawExternalConnected"] = false
        properties["ExternalConnected"] = true
        let unplugged = BatterySensor.decode(properties, at: now)
        suite.expect(unplugged.connected == false && unplugged.externalPowerConnected == true,
                     "physical unplug wins over a lagging effective-power flag")
        properties["AppleRawExternalConnected"] = "invalid"
        suite.expect(!BatterySensor.decode(properties, at: now).isFresh(at: now),
                     "malformed physical presence fails closed instead of assuming attachment")
        properties.removeValue(forKey: "AppleRawExternalConnected")
        suite.expect(BatterySensor.decode(properties, at: now).connected == true,
                     "legacy registry without a raw signal retains effective AC detection")
        properties["ExternalConnected"] = false
        suite.expect(BatterySensor.decode(properties, at: now).connected == false,
                     "legacy effective AC loss remains conservative when physical presence is unavailable")
    }

    #if !BATTERY_STANDALONE
    static func localizationAndBackup(_ suite: TestSuite) {
        for language in AppLanguage.allCases {
            let text = FeatureStrings.batteryCare(language)
            suite.expect(text.values.count == BatteryCareText.allCases.count, "battery locale covers every key: \(language)")
            suite.expect(text.values.allSatisfy { !$0.isEmpty }, "battery locale has no empty text: \(language)")
        }
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.batteryCarePolicy), "portable battery policy backed up")
        suite.expect(!SettingsBackupSupport.exportKeys().contains(DefaultsKey.batteryCareHelperVersion), "helper authority not portable")
        suite.expect(!SettingsBackupSupport.valueLooksRight(DefaultsKey.batteryCarePolicy, "{}"), "corrupt policy backup rejected")
    }
    #endif
}

final class FakeBatteryTransport: BatteryKeyTransport {
    var values: [String: [UInt8]] = ["CHTE": [0, 0, 0, 0], "CHIE": [0]]
    var denyWrites = false
    var ignoreWrites = false
    var wrongShape = false
    var writeCount = 0

    func inspectKey(named name: String) throws -> SMCClient.Key {
        .init(code: 0, name: name, dataSize: wrongShape ? 2 : name == "CHTE" ? 4 : 1,
              dataType: name == "CHTE" ? "ui32" : "hex_")
    }
    func checkedRead(_ key: SMCClient.Key) throws -> [UInt8] { values[key.name]! }
    func writeBytes(_ bytes: [UInt8], to key: SMCClient.Key) throws {
        writeCount += 1
        if denyWrites { throw BatteryHardwareError.unavailable }
        if !ignoreWrites { values[key.name] = bytes }
    }
}

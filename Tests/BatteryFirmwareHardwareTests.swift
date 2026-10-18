// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import Foundation

enum BatteryFirmwareHardwareTests {
    static func run(_ suite: TestSuite) {
        do {
            try commands(suite)
            try writeOrder(suite)
            try failures(suite)
            try controllerPolicy(suite)
            try exitAndSleep(suite)
        } catch { suite.expect(false, "firmware battery checks failed: \(error)") }
    }

    private static func commands(_ suite: TestSuite) throws {
        let fake = FakeFirmwareTransport(), hardware = try BatteryFirmwareHardware(transport: fake)
        hardware.prepare(upper: 80, target: 80)
        try hardware.apply(.charge)
        suite.expect(fake.values["bfF0"] == [2] && fake.values["bfD0"] == [80, 0, 0, 0]
            && fake.values["bfE0"] == [79, 0, 0, 0] && fake.values["CHIE"] == [0],
            "charge sets the firmware ceiling at the upper limit and resumes one point below")
        suite.expect(try hardware.readState() == .charge, "an active ceiling above 1 reads as charge")
        try hardware.apply(.hold)
        suite.expect(try fake.values["bfD0"] == [1, 0, 0, 0] && fake.values["bfE0"] == [0, 0, 0, 0]
            && hardware.readState() == .hold, "hold lowers the ceiling to 1 so charging stops")
        try hardware.apply(.discharge)
        suite.expect(try fake.values["CHIE"] == [8] && fake.values["bfD0"] == [1, 0, 0, 0]
            && hardware.readState() == .discharge, "discharge keeps charging stopped and cuts adapter power")
        hardware.prepare(upper: 100, target: 80)
        try hardware.apply(.charge)
        suite.expect(fake.values["bfF0"] == [0] && fake.values["CHIE"] == [0],
                     "a 100% ceiling turns the limiter off instead of writing 100")
        try hardware.apply(.system)
        suite.expect(fake.values["bfF0"] == [0] && fake.values["CHIE"] == [0], "return to macOS clears both controls")
    }

    private static func writeOrder(_ suite: TestSuite) throws {
        let fake = FakeFirmwareTransport(), hardware = try BatteryFirmwareHardware(transport: fake)
        hardware.prepare(upper: 80, target: 80)
        try hardware.apply(.charge)
        suite.expect(fake.writeKeys == ["bfD0", "bfE0", "bfF0"],
                     "thresholds change while the limiter is off, then it turns on")
        fake.writeKeys.removeAll()
        try hardware.apply(.charge)
        suite.expect(fake.writeKeys.isEmpty && !hardware.needsApply(.charge), "an unchanged limit performs no writes")
        try hardware.apply(.discharge)
        fake.writeKeys.removeAll()
        try hardware.apply(.charge)
        suite.expect(fake.writeKeys.first == "CHIE", "ending discharge reconnects adapter power first")
        hardware.prepare(upper: 85, target: 80)
        suite.expect(hardware.needsApply(.charge), "a new upper limit needs a firmware write")
    }

    private static func failures(_ suite: TestSuite) throws {
        let fake = FakeFirmwareTransport(), hardware = try BatteryFirmwareHardware(transport: fake)
        hardware.prepare(upper: 80, target: 80)
        try hardware.apply(.charge)
        fake.values["bfD0"] = [90, 0, 0, 0]
        suite.expect((try? hardware.verifyOwnership()) == nil, "another writer's ceiling is detected")
        fake.values["bfF0"] = [5]
        suite.expect((try? hardware.readState()) == nil, "an unknown limiter mode is a conflict")
        fake.values["bfF0"] = [0]
        fake.ignoreWrites = true
        suite.expect((try? hardware.apply(.charge)) == nil, "write success without readback change is rejected")
        fake.ignoreWrites = false
        fake.missing = "bfE0"
        suite.expect((try? BatteryFirmwareHardware(transport: fake)) == nil, "older firmware without the keys is unavailable")
        fake.missing = nil
        fake.wrongShape = true
        suite.expect((try? BatteryFirmwareHardware(transport: fake)) == nil, "wrong key sizes are unavailable")
    }

    private static func controllerPolicy(_ suite: TestSuite) throws {
        let fixture = FirmwareControllerFixture(), controller = fixture.controller()
        controller.probe(); controller.tick()
        suite.expect(controller.snapshot.controlBackend == "firmware-limit" && controller.snapshot.command == .charge
            && fixture.fake.values["bfD0"] == [80, 0, 0, 0], "a qualified policy below 75 charges under an 80 ceiling")
        fixture.percent = 80; controller.tick()
        suite.expect(controller.snapshot.command == .hold && fixture.fake.values["bfD0"] == [1, 0, 0, 0],
                     "reaching the upper limit holds")
        fixture.percent = 77; controller.tick()
        suite.expect(controller.snapshot.command == .hold, "a drop inside the range does not restart charging")
        fixture.percent = 74; controller.tick()
        suite.expect(controller.snapshot.command == .charge, "charging resumes below the lower limit")
    }

    private static func exitAndSleep(_ suite: TestSuite) throws {
        let fixture = FirmwareControllerFixture(), controller = fixture.controller()
        controller.probe(); fixture.percent = 80; controller.tick()
        controller.powerChange(sleep: true)
        suite.expect(controller.snapshot.command == .charge && fixture.fake.values["bfD0"] == [80, 0, 0, 0],
                     "sleep leaves the firmware ceiling in force instead of an unmonitored hold")
        controller.powerChange(sleep: false)
        var restored: Bool?
        controller.shutdown { restored = $0 }
        controller.queue.sync {}
        suite.expect(restored == true && fixture.fake.values["bfF0"] == [2] && fixture.fake.values["bfD0"] == [80, 0, 0, 0]
            && fixture.fake.values["CHIE"] == [0] && fixture.store.state.ownsHardware,
            "helper exit keeps the saved ceiling so charging cannot pass it while away")
        var policy = controller.state.policy; policy.enabled = false
        suite.expect(controller.configure(policy) && fixture.fake.values["bfF0"] == [0],
                     "disabling Aster returns charging to macOS")
    }
}

private final class FirmwareControllerFixture {
    let store = MemoryBatteryStore()
    let fake = FakeFirmwareTransport()
    var percent = 60

    init() {
        store.state.policy.enabled = true
        store.state.qualifiedFingerprint = "fixture"
        store.state.chargeQualified = true; store.state.dischargeQualified = true
    }

    func controller() -> BatteryController {
        BatteryController(journal: store, automaticallyStart: false,
            makeHardware: { [fake] in try BatteryFirmwareHardware(transport: fake) },
            readSample: { [self] in sample() }, readCompetitors: { [] }, fingerprint: "fixture")
    }

    private func sample() -> BatterySample {
        let limited = fake.values["bfF0"] == [2], ceiling = Int(fake.values["bfD0"]![0])
        let draining = fake.values["CHIE"] == [8], charging = !draining && (!limited || ceiling > percent)
        return .init(at: Date(), percent: percent, temperature: 30, connected: true,
                     charging: charging, watts: draining ? -10 : charging ? 10 : 0)
    }
}

final class FakeFirmwareTransport: BatteryKeyTransport {
    var values: [String: [UInt8]] = ["bfF0": [0], "bfD0": [100, 0, 0, 0], "bfE0": [99, 0, 0, 0], "CHIE": [0]]
    var ignoreWrites = false, wrongShape = false
    var missing: String?
    var writeKeys: [String] = []

    func inspectKey(named name: String) throws -> SMCClient.Key {
        guard name != missing, values[name] != nil else { throw SMCClient.WriteError.controller(132) }
        let size: UInt32 = wrongShape ? 2 : name == "bfD0" || name == "bfE0" ? 4 : 1
        return .init(code: 0, name: name, dataSize: size, dataType: name == "CHIE" ? "hex_" : "ui8 ")
    }
    func checkedRead(_ key: SMCClient.Key) throws -> [UInt8] { values[key.name]! }
    func writeBytes(_ bytes: [UInt8], to key: SMCClient.Key) throws {
        writeKeys.append(key.name)
        if !ignoreWrites { values[key.name] = bytes }
    }
}

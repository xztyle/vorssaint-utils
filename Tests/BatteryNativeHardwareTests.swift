// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import Foundation

enum BatteryNativeHardwareTests {
    static func run(_ suite: TestSuite) {
        do {
            try registration(suite)
            try commandPlans(suite)
            try durableOwnership(suite)
            try conflicts(suite)
            try archivedForeignRule(suite)
            try recoveryBudget(suite)
            try removalRecovery(suite)
            try ownerRestart(suite)
            try oldJournal(suite)
        } catch { suite.expect(false, "native battery checks failed: \(error)") }
    }

    private static func archivedForeignRule(_ suite: TestSuite) throws {
        let fixture = NativeBatteryFixture(), hardware = try fixture.hardware()
        try hardware.apply(.hold)
        var root = try PropertyListSerialization.propertyList(from: fixture.io.data!, format: nil) as! [String: Any]
        var objects = root["$objects"] as! [Any]
        let index = objects.firstIndex { ($0 as? String) == BatteryNativePolicyArchive.reason }!
        objects[index] = "manualChargeLimit"; root["$objects"] = objects
        fixture.io.data = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
        fixture.io.live = []
        let reloads = fixture.io.reloads
        suite.expect((try? fixture.hardware()) == nil && fixture.io.reloads == reloads,
                     "an inactive-looking but unterminated foreign archived rule is never revived by import")
    }

    private static func registration(_ suite: TestSuite) throws {
        let fixture = NativeBatteryFixture()
        let lease = fixture.newLease()
        let valid = NativeBatteryIO.rows(lease)
        suite.expect(try NativeBatteryIO.registration(valid).confirms(lease, owner: lease.owner), "registration requires owned and effective rows")
        suite.expect(!(try NativeBatteryIO.registration([valid[1], valid[1]])).confirms(lease, owner: lease.owner), "duplicate effective rows cannot impersonate the helper")
        for (key, value): (String, Any) in [("chargeSocLimitOwner", true), ("chargeSocLimitSoc", 80.9),
            ("chargeSocLimitDrain", "YES"), ("chargeSocLimitOwner", "-1"), ("Terminated", 2)] {
            var bad = valid; bad[0][key] = value
            suite.expect((try? NativeBatteryIO.registration(bad)) == nil, "malformed live field \(key) is refused")
        }
        var manual = valid[1]; manual["chargeSocLimitReason"] = "manualChargeLimit"
        suite.expect(try NativeBatteryIO.registration([manual]).hasOtherOwner, "a system effective manual rule is a conflict")
        suite.expect((try? BatteryNativeRegistration(output: "unavailable")) == nil, "unknown pmset output never means no rules")
    }

    private static func commandPlans(_ suite: TestSuite) throws {
        let fixture = NativeBatteryFixture(), hardware = try fixture.hardware()
        hardware.prepare(upper: 80, target: 77, hold: 75)
        try hardware.apply(.hold)
        suite.expect(fixture.lease?.target == 75 && fixture.lease?.drain == false && (try? hardware.readState()) == .hold,
                     "hold pauses at a real ceiling below the upper limit, never powerd's ignored 1%")
        try hardware.apply(.discharge)
        suite.expect(fixture.lease?.target == 77 && fixture.lease?.drain == true, "discharge uses the operation's requested target")
        try hardware.apply(.charge)
        suite.expect(fixture.lease?.target == 80 && fixture.lease?.drain == false, "charge remains bounded by Aster's upper limit")
        let reloads = fixture.io.reloads
        try hardware.apply(.charge); try hardware.verifyOwnership()
        suite.expect(fixture.io.reloads == reloads, "healthy unchanged policy never restarts the power service")
        hardware.prepare(upper: 85, target: 85, hold: 75)
        suite.expect(hardware.needsApply(.charge), "editing the limit refreshes an unchanged charge command")
        try hardware.apply(.charge)
        suite.expect(fixture.lease?.target == 85, "new upper limit is applied immediately")
        hardware.prepare(upper: 100, target: 80, hold: 75); try hardware.apply(.charge)
        suite.expect(fixture.lease == nil && fixture.io.live.isEmpty, "one-time full charge removes only Aster's rule")
    }

    private static func durableOwnership(_ suite: TestSuite) throws {
        let fixture = NativeBatteryFixture(), hardware = try fixture.hardware()
        fixture.failSave = true
        suite.expect((try? hardware.apply(.hold)) == nil && fixture.io.writes == 0 && fixture.io.reloads == 0,
                     "failed journal save prevents every system write and restart")
        fixture.failSave = false; fixture.io.failWrite = true
        suite.expect((try? hardware.apply(.hold)) == nil && fixture.lease != nil && fixture.io.reloads == 0,
                     "failed policy write retains the journaled token for recovery")
        fixture.io.failWrite = false; fixture.time += 61
        try hardware.apply(.hold)
        suite.expect(fixture.io.wroteAfterJournal, "durable ownership always precedes the native preferences write")
        fixture.failSave = true
        let writes = fixture.io.writes
        suite.expect((try? hardware.apply(.system)) == nil && fixture.io.writes == writes, "failed removal journal prevents mutation")
    }

    private static func conflicts(_ suite: TestSuite) throws {
        let fixture = NativeBatteryFixture(), hardware = try fixture.hardware()
        try hardware.apply(.hold)
        var foreign = NativeBatteryIO.rows(fixture.lease!)[0]
        foreign["chargeSocLimitReason"] = "manualChargeLimit"; foreign["chargeSocLimitOwner"] = 6789
        fixture.io.live.append(foreign)
        let writes = fixture.io.writes, reloads = fixture.io.reloads
        suite.expect((try? hardware.verifyOwnership()) == nil, "foreign policy stops ownership recovery")
        suite.expect((try? hardware.apply(.hold)) == nil && fixture.io.writes == writes && fixture.io.reloads == reloads,
                     "even a healthy own rule cannot overwrite a new foreign rule")
        fixture.io.live = []
        let document = try BatteryNativePolicyArchive(data: fixture.io.data!)
        fixture.io.data = try document.replacing(token: Data(16..<32), previousOwner: nil, owner: 6789, target: 70, drain: false)
        fixture.time += 61
        suite.expect((try? hardware.apply(.hold)) == nil && fixture.io.writes == writes,
                     "an unjournaled second Aster token cannot be taken over")
    }

    private static func recoveryBudget(_ suite: TestSuite) throws {
        let fixture = NativeBatteryFixture(), hardware = try fixture.hardware()
        try hardware.apply(.hold)
        fixture.io.live = []
        suite.expect((try? hardware.verifyOwnership()) == nil && fixture.io.reloads == 1, "missing lease repair waits for its cooldown")
        fixture.time += 61; try hardware.verifyOwnership()
        suite.expect(fixture.io.reloads == 2 && !fixture.io.live.isEmpty, "lost rule self-recovers after cooldown")
        fixture.io.live = []; fixture.time += 61; try hardware.verifyOwnership()
        fixture.io.live = []; fixture.time += 61
        suite.expect((try? hardware.verifyOwnership()) == nil && fixture.io.reloads == 3, "repair stops after three restarts in ten minutes")
        fixture.time += 601; try hardware.verifyOwnership()
        suite.expect(fixture.io.reloads == 4, "recovery resumes after the bounded repair window")
    }

    private static func removalRecovery(_ suite: TestSuite) throws {
        let fixture = NativeBatteryFixture(), hardware = try fixture.hardware()
        try hardware.apply(.hold)
        fixture.io.failReload = true
        suite.expect((try? hardware.apply(.system)) == nil && fixture.lease?.removalPending == true,
                     "failed removal import retains durable recovery authority")
        let reloads = fixture.io.reloads
        suite.expect((try? hardware.apply(.system)) == nil && fixture.io.reloads == reloads, "removal retries cannot cause a restart storm")
        fixture.time += 61; fixture.io.failReload = false
        try hardware.apply(.system)
        suite.expect(fixture.lease == nil && fixture.io.live.isEmpty, "recovery clears receipt only after owned registration disappears")
    }

    private static func ownerRestart(_ suite: TestSuite) throws {
        let fixture = NativeBatteryFixture(), hardware = try fixture.hardware()
        try hardware.apply(.hold)
        let token = fixture.lease!.token
        fixture.io.live = [] // macOS releases a dead helper's resident lease.
        let restarted = try fixture.hardware(owner: 3456)
        try restarted.apply(.hold)
        suite.expect(fixture.lease?.token == token && fixture.lease?.owner == 3456,
                     "a replacement helper reclaims only its journaled token")
        try restarted.apply(.system)
        suite.expect(fixture.lease == nil, "replacement helper can release its recovered lease")
        fixture.io.boot = UUID().uuidString; fixture.io.data = Data("old archive".utf8)
        let nextBoot = try fixture.hardware()
        try nextBoot.apply(.hold)
        suite.expect(fixture.lease?.boot == fixture.io.boot, "new boot begins only after two empty live-policy reads")
    }

    private static func oldJournal(_ suite: TestSuite) throws {
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        var json = try JSONSerialization.jsonObject(with: encoder.encode(BatteryCareState())) as! [String: Any]
        json.removeValue(forKey: "nativeLease")
        let decoded = try decoder.decode(BatteryCareState.self, from: JSONSerialization.data(withJSONObject: json))
        suite.expect(decoded.isValid && decoded.nativeLease == nil, "existing journals remain readable without a native lease field")
    }
}

final class NativeBatteryFixture {
    let io = NativeBatteryIO()
    var lease: BatteryNativeLease?
    var failSave = false
    var time: TimeInterval = 1_000_000

    func newLease() -> BatteryNativeLease {
        .init(token: Data(0..<16), boot: io.boot, owner: 2345, target: 80, drain: false)
    }

    func hardware(owner: Int = 2345) throws -> BatteryNativeHardware {
        io.journalReady = { [weak self] in self?.lease != nil }
        return try BatteryNativeHardware(io: io, owner: owner, load: { [weak self] in self?.lease }, save: { [weak self] value in
            guard let self, !failSave else { throw BatteryHardwareError.unavailable }
            lease = value
        }, now: { [weak self] in Date(timeIntervalSince1970: self?.time ?? 0) })
    }
}

final class NativeBatteryIO: BatteryNativePolicyTransport {
    var boot = UUID().uuidString
    var archiveBoot: String?
    var data: Data?
    var live: [[String: Any]] = []
    var writes = 0, reloads = 0
    var failWrite = false, failReload = false
    var wroteAfterJournal = false
    var journalReady: () -> Bool = { false }

    func bootIdentifier() throws -> String { boot }
    func snapshot() throws -> BatteryNativePolicySnapshot { .init(boot: archiveBoot, data: data) }
    func registration() throws -> BatteryNativeRegistration { try Self.registration(live) }

    func write(_ data: Data, boot: String, basedOn: BatteryNativePolicySnapshot) throws {
        guard !failWrite else { throw BatteryHardwareError.unavailable }
        writes += 1; wroteAfterJournal = journalReady(); self.data = data; archiveBoot = boot
    }

    func reload() throws {
        reloads += 1
        guard !failReload else { throw BatteryHardwareError.unavailable }
        let document = try BatteryNativePolicyArchive(data: data!)
        live = document.records.flatMap { record in
            Self.rows(.init(token: record.token, boot: boot, owner: record.owner, target: record.target, drain: record.drain))
        }
    }

    static func registration(_ rows: [[String: Any]]) throws -> BatteryNativeRegistration {
        let bytes = try PropertyListSerialization.data(fromPropertyList: rows, format: .xml, options: 0)
        return try .init(output: "Battery level limits:\n" + String(decoding: bytes, as: UTF8.self))
    }

    static func rows(_ lease: BatteryNativeLease) -> [[String: Any]] {
        [lease.owner, 0].map { owner in
            ["chargeSocLimitOwner": owner, "chargeSocLimitReason": BatteryNativePolicyArchive.reason,
             "chargeSocLimitSoc": lease.target, "chargeSocLimitDrain": lease.drain ? 1 : 0,
             "chargeSocLimitNoChargeToFull": 1, "chargeSocLimitIsEOC": 1, "Terminated": 0]
        }
    }
}

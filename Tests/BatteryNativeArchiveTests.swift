// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import Foundation

enum BatteryNativeArchiveTests {
    static let first = Data(0..<16)
    static let second = Data(16..<32)

    static func run(_ suite: TestSuite) {
        do {
            let empty = try BatteryNativePolicyArchive(data: BatteryNativePolicyArchive.empty())
            suite.expect(empty.records.isEmpty, "native archive starts empty without battery writes")
            let created = try empty.replacing(token: first, previousOwner: nil, owner: 2345, target: 80, drain: false)
            let policy = try BatteryNativePolicyArchive(data: created)
            suite.expect(policy.records.count == 1 && policy.records[0].owner == 2345 && policy.records[0].target == 80,
                         "Aster's native rule has its own owner and target")
            suite.expect(!policy.records[0].drain && policy.records[0].noChargeToFull && policy.records[0].isEndOfCharge,
                         "holding uses no-drain and no-charge-to-full flags")
            suite.expect(try policy.replacing(token: first, previousOwner: 2345, owner: 2345, target: 80, drain: false) == created,
                         "unchanged lease preserves exact bytes and needs no reload")
            try changes(policy, suite)
            try isolation(policy, suite)
            try malformed(policy, suite)
        } catch { suite.expect(false, "native archive checks failed: \(error)") }
    }

    private static func changes(_ policy: BatteryNativePolicyArchive, _ suite: TestSuite) throws {
        let updated = try BatteryNativePolicyArchive(data: policy.replacing(token: first, previousOwner: 2345,
            owner: 6789, target: 75, drain: true))
        suite.expect(updated.records.count == 1 && updated.records[0].owner == 6789 && updated.records[0].drain,
                     "a journaled owner change replaces only Aster's lease")
        suite.expect((try? policy.replacing(token: first, previousOwner: 999, owner: 6789, target: 75, drain: false)) == nil,
                     "an unexpected owner stops mutation")
        let removed = try BatteryNativePolicyArchive(data: updated.removing(token: first, previousOwner: 6789))
        suite.expect(removed.records.isEmpty, "stopping removes the owned policy")
        suite.expect(try removed.removing(token: first, previousOwner: 6789) == removed.data,
                     "an already removed lease changes nothing")
        for target in [-1, 0, 100, 101, Int.max] {
            suite.expect((try? policy.replacing(token: second, previousOwner: nil, owner: 6789, target: target, drain: false)) == nil,
                         "invalid ceilings cannot enter an archive")
        }
        suite.expect((try? policy.replacing(token: second, previousOwner: nil, owner: 1, target: 80, drain: false)) == nil,
                     "a lease never impersonates init or a system owner")
    }

    private static func isolation(_ policy: BatteryNativePolicyArchive, _ suite: TestSuite) throws {
        let two = try BatteryNativePolicyArchive(data: policy.replacing(token: second, previousOwner: nil,
            owner: 5678, target: 70, drain: false))
        let removed = try BatteryNativePolicyArchive(data: two.removing(token: first, previousOwner: 2345))
        suite.expect(removed.records.count == 1 && removed.records[0].token == second && removed.records[0].target == 70,
                     "removal preserves another lease")
        let foreign = try mutate(policy.data) { root in
            var objects = root["$objects"] as! [Any]
            let reason = objects.firstIndex { ($0 as? String) == BatteryNativePolicyArchive.reason }!
            objects[reason] = "another.app.battery"; root["$objects"] = objects
            root["Unrelated"] = Data([9, 8, 7])
        }
        let other = try BatteryNativePolicyArchive(data: foreign)
        suite.expect((try? other.removing(token: first, previousOwner: 2345)) == nil, "a foreign reason cannot be removed")
        suite.expect((try? other.replacing(token: first, previousOwner: 2345, owner: 5678, target: 80, drain: false)) == nil,
                     "a token collision cannot take another client's lease")
        let added = try other.replacing(token: second, previousOwner: nil, owner: 5678, target: 80, drain: false)
        let root = try PropertyListSerialization.propertyList(from: added, format: nil) as! [String: Any]
        suite.expect(root["Unrelated"] as? Data == Data([9, 8, 7]), "unknown archive fields survive an Aster-only edit")
    }

    private static func malformed(_ policy: BatteryNativePolicyArchive, _ suite: TestSuite) throws {
        suite.expect((try? BatteryNativePolicyArchive(data: Data("invalid".utf8))) == nil, "malformed native archive is refused")
        suite.expect((try? BatteryNativePolicyArchive(data: Data(repeating: 0, count: 1_048_577))) == nil,
                     "native archive size is bounded")
        for (key, value): (String, Any) in [("owner", true), ("soclimit", 80.5), ("drain", 2),
                                            ("owner", -1), ("owner", Int64(Int32.max) + 1)] {
            let bad = try mutate(policy.data) { root in
                var objects = root["$objects"] as! [Any]
                var item = objects[policy.records[0].index] as! [String: Any]
                item[key] = value; objects[policy.records[0].index] = item; root["$objects"] = objects
            }
            suite.expect((try? BatteryNativePolicyArchive(data: bad)) == nil, "invalid native field \(key) fails closed")
        }
        let duplicate = try mutate(policy.data) { root in
            var objects = root["$objects"] as! [Any]
            let index = objects.firstIndex { ($0 as? [String: Any])?["NS.objects"] is [Any] }!
            var array = objects[index] as! [String: Any]
            let refs = array["NS.objects"] as! [Any]
            array["NS.objects"] = refs + refs; objects[index] = array; root["$objects"] = objects
        }
        suite.expect((try? BatteryNativePolicyArchive(data: duplicate)) == nil, "duplicate policy tokens cannot be edited")
    }

    private static func mutate(_ data: Data, _ action: (inout [String: Any]) -> Void) throws -> Data {
        var root = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
        action(&root)
        return try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
    }
}

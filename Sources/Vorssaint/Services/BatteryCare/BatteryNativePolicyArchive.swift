// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors
// Archive schema researched from MIT-licensed Battery macOS 27 compatibility
// patch, revision 2124764eef17aaba4b0f1ea97969d79185609029. See ThirdPartyNotices.

import Foundation
import CoreFoundation

/// Parses property-list objects without unarchiving or instantiating a class.
/// Only Aster's journaled UUID and reason may be edited. Unrelated data survives.
struct BatteryNativePolicyArchive {
    static let reason = "io.github.xztyle.Aster.battery-care"
    struct Record: Equatable {
        let index: Int
        let token: Data
        let reason: String
        let owner: Int
        let target: Int
        let drain: Bool
        let noChargeToFull: Bool
        let isEndOfCharge: Bool
        let terminated: Bool
    }
    enum Failure: Error { case malformed, foreignToken, changedOwner, invalidRequest }
    let data: Data
    private let root: [String: Any]
    private let objects: [Any]
    private let arrayIndex: Int
    let records: [Record]

    init(data: Data) throws {
        guard data.count <= 1_048_576,
              let root = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              root["$archiver"] as? String == "NSKeyedArchiver", Self.integer(root["$version"], 100_000...100_000) != nil,
              let objects = root["$objects"] as? [Any], objects.count <= 1024,
              let top = root["$top"] as? [String: Any], let arrayIndex = Self.index(top["root"], count: objects.count),
              let array = objects[arrayIndex] as? [String: Any],
              ["NSArray", "NSMutableArray"].contains(Self.className(array, objects: objects) ?? ""),
              let refs = array["NS.objects"] as? [Any], refs.count <= 64 else { throw Failure.malformed }
        let records = try refs.map { try Self.record($0, objects: objects) }
        guard Set(records.map(\.token)).count == records.count,
              Set(records.map(\.index)).count == records.count else { throw Failure.malformed }
        self.data = data; self.root = root; self.objects = objects
        self.arrayIndex = arrayIndex; self.records = records
    }

    private static func record(_ reference: Any, objects: [Any]) throws -> Record {
        guard let objectIndex = index(reference, count: objects.count), let item = objects[objectIndex] as? [String: Any],
              className(item, objects: objects) == "ChargeCtrlPolicy",
              let owner = integer(item["owner"], 0...Int(Int32.max)), let target = integer(item["soclimit"], 1...100),
              let drain = flag(item["drain"]), let full = flag(item["noChargeToFull"]),
              let end = flag(item["isEndOfCharge"]), let terminated = flag(item["terminated"]),
              let reasonIndex = index(item["reason"], count: objects.count),
              let reason = objects[reasonIndex] as? String, reason.utf8.count <= 512,
              let uuidIndex = index(item["token"], count: objects.count),
              let uuid = objects[uuidIndex] as? [String: Any], className(uuid, objects: objects) == "NSUUID",
              let token = uuid["NS.uuidbytes"] as? Data, token.count == 16 else { throw Failure.malformed }
        return .init(index: objectIndex, token: token, reason: reason, owner: owner, target: target,
                     drain: drain, noChargeToFull: full, isEndOfCharge: end, terminated: terminated)
    }

    private static func integer(_ value: Any?, _ range: ClosedRange<Int>) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue.rounded() == number.doubleValue,
              Double(range.lowerBound)...Double(range.upperBound) ~= number.doubleValue else { return nil }
        return number.intValue
    }

    private static func flag(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, [0.0, 1.0].contains(number.doubleValue) else { return nil }
        return number.boolValue
    }

    private static func className(_ item: [String: Any], objects: [Any]) -> String? {
        guard let index = index(item["$class"], count: objects.count),
              let description = objects[index] as? [String: Any],
              let name = description["$classname"] as? String,
              let classes = description["$classes"] as? [String], (1...8).contains(classes.count),
              classes.first == name, classes.last == "NSObject",
              classes.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 128 }) else { return nil }
        return name
    }

    private static func index(_ reference: Any?, count: Int) -> Int? {
        guard let reference, !(reference is [String: Any]), !(reference is [Any]),
              let xml = try? PropertyListSerialization.data(fromPropertyList: reference, format: .xml, options: 0),
              xml.count < 1024, let string = String(data: xml, encoding: .utf8),
              let match = string.range(of: "<dict>\\s*<key>CF\\$UID</key>\\s*<integer>[0-9]{1,9}</integer>\\s*</dict>",
                                       options: .regularExpression) else { return nil }
        let fragment = String(string[match])
        guard let begin = fragment.range(of: "<integer>"), let end = fragment.range(of: "</integer>"),
              let index = Int(fragment[begin.upperBound..<end.lowerBound]), (0..<count).contains(index) else { return nil }
        return index
    }

    private static func reference(_ index: Int) throws -> Any {
        let xml = "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>CF$UID</key><integer>\(index)</integer></dict></plist>"
        return try PropertyListSerialization.propertyList(from: Data(xml.utf8), format: nil)
    }

    static func empty() throws -> Data {
        try NSKeyedArchiver.archivedData(withRootObject: NSMutableArray(), requiringSecureCoding: true)
    }

    func replacing(token: Data, previousOwner: Int?, owner: Int, target: Int, drain: Bool) throws -> Data {
        guard token.count == 16, owner > 1, owner <= Int(Int32.max), (1..<100).contains(target) else { throw Failure.invalidRequest }
        let existing = try owned(token, previousOwner: previousOwner)
        if let existing, existing.owner == owner, existing.target == target, existing.drain == drain,
           existing.noChargeToFull, existing.isEndOfCharge, !existing.terminated { return data }
        var objects = self.objects
        let index = try existing?.index ?? append(token: token, to: &objects)
        var item = objects[index] as! [String: Any]
        item["owner"] = owner; item["soclimit"] = target; item["drain"] = drain
        item["noChargeToFull"] = true; item["isEndOfCharge"] = true; item["terminated"] = false
        objects[index] = item
        return try encoded(objects)
    }

    func removing(token: Data, previousOwner: Int) throws -> Data {
        guard token.count == 16 else { throw Failure.invalidRequest }
        guard let record = try owned(token, previousOwner: previousOwner) else { return data }
        var objects = self.objects
        var array = objects[arrayIndex] as! [String: Any]
        array["NS.objects"] = (array["NS.objects"] as! [Any]).filter { Self.index($0, count: objects.count) != record.index }
        objects[arrayIndex] = array
        return try encoded(objects)
    }

    private func owned(_ token: Data, previousOwner: Int?) throws -> Record? {
        guard let existing = records.first(where: { $0.token == token }) else { return nil }
        guard existing.reason == Self.reason else { throw Failure.foreignToken }
        guard previousOwner == existing.owner else { throw Failure.changedOwner }
        return existing
    }

    private func append(token: Data, to objects: inout [Any]) throws -> Int {
        guard objects.count <= 1000, records.count < 64 else { throw Failure.malformed }
        let policyClass = objects.count
        objects.append(["$classname": "ChargeCtrlPolicy", "$classes": ["ChargeCtrlPolicy", "NSObject"]])
        let uuidClass = objects.count
        objects.append(["$classname": "NSUUID", "$classes": ["NSUUID", "NSObject"]])
        let uuidIndex = objects.count
        objects.append(["$class": try Self.reference(uuidClass), "NS.uuidbytes": token])
        let reasonIndex = objects.count
        objects.append(Self.reason)
        let index = objects.count
        objects.append(["$class": try Self.reference(policyClass), "token": try Self.reference(uuidIndex),
                        "reason": try Self.reference(reasonIndex)])
        var array = objects[arrayIndex] as! [String: Any]
        var references = array["NS.objects"] as! [Any]
        references.append(try Self.reference(index)); array["NS.objects"] = references
        objects[arrayIndex] = array
        return index
    }

    private func encoded(_ objects: [Any]) throws -> Data {
        var root = self.root; root["$objects"] = objects
        let data = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
        _ = try Self(data: data)
        return data
    }
}

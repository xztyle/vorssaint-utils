// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import Foundation
import CoreFoundation

struct BatteryNativeLease: Codable, Equatable {
    var token: Data
    var boot: String
    var owner: Int
    var target: Int
    var drain: Bool
    var removalPending = false
    var attempts: [Date] = []

    var isValid: Bool {
        token.count == 16 && UUID(uuidString: boot) != nil && (2...Int(Int32.max)).contains(owner)
            && (1..<100).contains(target) && attempts.count <= 3
            && attempts.allSatisfy { $0.timeIntervalSince1970.isFinite }
    }

    static func token() -> Data {
        var bytes = UUID().uuid
        return withUnsafeBytes(of: &bytes) { Data($0) }
    }
}

struct BatteryNativeRegistration {
    let rows: [[String: Any]]

    init(output: String) throws {
        guard output.utf8.count < 65_536 else { throw BatteryHardwareError.shape }
        if output.trimmingCharacters(in: .whitespacesAndNewlines) == "No battery level limits set" { rows = []; return }
        guard output.hasPrefix("Battery level limits:\n"), let begin = output.firstIndex(of: "\n"),
              let rows = try PropertyListSerialization.propertyList(from: Data(output[output.index(after: begin)...].utf8),
                                                                   format: nil) as? [[String: Any]],
              rows.count <= 64, rows.allSatisfy(Self.validRow) else { throw BatteryHardwareError.shape }
        self.rows = rows
    }

    func confirms(_ lease: BatteryNativeLease, owner: Int) -> Bool {
        let expected = rows.filter { Self.int($0["chargeSocLimitOwner"]) == owner || Self.int($0["chargeSocLimitOwner"]) == 0 }
        return expected.count == 2 && Set(expected.compactMap { Self.int($0["chargeSocLimitOwner"]) }) == [0, owner]
            && expected.allSatisfy {
            $0["chargeSocLimitReason"] as? String == BatteryNativePolicyArchive.reason
                && Self.int($0["chargeSocLimitSoc"]) == lease.target && Self.int($0["chargeSocLimitDrain"]) == (lease.drain ? 1 : 0)
                && Self.int($0["chargeSocLimitNoChargeToFull"]) == 1 && Self.int($0["chargeSocLimitIsEOC"]) == 1
                && Self.int($0["Terminated"]) == 0
        }
    }

    var hasOtherOwner: Bool {
        rows.contains { $0["chargeSocLimitReason"] as? String != BatteryNativePolicyArchive.reason }
    }

    func containsOwner(_ owner: Int) -> Bool {
        rows.contains { Self.int($0["chargeSocLimitOwner"]) == owner && $0["chargeSocLimitReason"] as? String == BatteryNativePolicyArchive.reason }
    }

    private static func validRow(_ row: [String: Any]) -> Bool {
        guard let reason = row["chargeSocLimitReason"] as? String, !reason.isEmpty, reason.utf8.count <= 512,
              let owner = int(row["chargeSocLimitOwner"]), (0...Int(Int32.max)).contains(owner),
              let target = int(row["chargeSocLimitSoc"]), (1...100).contains(target) else { return false }
        return ["chargeSocLimitDrain", "chargeSocLimitNoChargeToFull", "chargeSocLimitIsEOC", "Terminated"]
            .allSatisfy { int(row[$0]).map { (0...1).contains($0) } == true }
    }

    private static func int(_ value: Any?) -> Int? {
        if let string = value as? String {
            guard !string.isEmpty, string.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
            return Int(string)
        }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue.rounded() == number.doubleValue,
              (0...Double(Int32.max)).contains(number.doubleValue) else { return nil }
        return number.intValue
    }
}

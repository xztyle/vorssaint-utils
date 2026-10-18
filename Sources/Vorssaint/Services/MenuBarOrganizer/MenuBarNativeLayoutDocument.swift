// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import Foundation
import CoreFoundation

struct MenuBarNativeLayoutDocument {
    static let positionsKey = "TrailingItemPreferredPositions"
    let data: Data
    let root: [String: Any]
    let format: PropertyListSerialization.PropertyListFormat
    let positions: [String: Double]

    init(data: Data) throws {
        guard data.count <= 2_097_152 else { throw CocoaError(.fileReadTooLarge) }
        var format = PropertyListSerialization.PropertyListFormat.binary
        guard let root = try PropertyListSerialization.propertyList(from: data, format: &format) as? [String: Any],
              let values = root[Self.positionsKey] as? [String: Any], values.count <= 1024 else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        var positions: [String: Double] = [:]
        for (key, value) in values {
            guard !key.isEmpty, key.utf8.count <= 512, let number = value as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite,
                  abs(number.doubleValue) <= 10_000_000 else {
                throw CocoaError(.propertyListReadCorrupt)
            }
            positions[key] = number.doubleValue
        }
        self.data = data; self.root = root; self.format = format; self.positions = positions
    }

    func replacing(_ changes: [String: Double]) throws -> Data {
        guard changes.keys.allSatisfy({ positions[$0] != nil }),
              changes.values.allSatisfy({ $0.isFinite && (-10_000_000...10_000_000).contains($0) }) else { throw CocoaError(.coderInvalidValue) }
        var root = self.root
        var values = root[Self.positionsKey] as! [String: Any]
        let accepted = values.values.compactMap { $0 as? NSNumber }
        for (key, value) in changes {
            values[key] = accepted.first { $0.doubleValue == value } ?? NSNumber(value: value)
        }
        root[Self.positionsKey] = values
        return try PropertyListSerialization.data(fromPropertyList: root, format: format, options: 0)
    }
}

enum MenuBarNativePositionPolicy {
    /// Permute existing accepted weights. Never invent a key, touch an unknown
    /// item, or move through an anchored system item.
    static func changes(current: [String], desired: [String], positions: [String: Double]) -> [String: Double]? {
        guard current.count > 1, current.count <= 500, Set(current).count == current.count,
              Set(current) == Set(desired), desired.count == current.count else { return nil }
        let weights = current.compactMap { positions[$0] }
        guard weights.count == current.count, Set(weights).count == weights.count,
              weights.allSatisfy(\.isFinite) else { return nil }
        let pairs = zip(weights, weights.dropFirst())
        guard pairs.allSatisfy({ $0 < $1 }) || pairs.allSatisfy({ $0 > $1 }) else { return nil }
        return Dictionary(uniqueKeysWithValues: zip(desired, weights).filter { positions[$0.0] != $0.1 })
    }
}

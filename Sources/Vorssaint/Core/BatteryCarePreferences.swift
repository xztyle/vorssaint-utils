// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import Foundation

extension DefaultsKey {
    static let batteryCarePolicy = "batteryCarePolicy"
    static let batteryCareHelperVersion = "batteryCareHelperVersion"
}

enum BatteryCarePreferences {
    static func decode(_ raw: String?) -> BatteryCarePolicy? {
        guard let data = raw?.data(using: .utf8), data.count <= 65536,
              let policy = try? JSONDecoder().decode(BatteryCarePolicy.self, from: data),
              policy.isValid else { return nil }
        return policy
    }

    static func encode(_ policy: BatteryCarePolicy) -> String {
        guard policy.isValid, let data = try? JSONEncoder().encode(policy) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import Foundation

enum BatteryControlCompatibility {
    /// A failed legacy key or entitlement denial is not a pending power-flow test.
    /// Keep the user's policy intact, but do not present it as active protection.
    static func isRestricted(_ snapshot: BatteryCareSnapshot) -> Bool {
        guard !snapshot.chargeCandidate, snapshot.qualificationStep == nil,
              snapshot.reason == .unavailable, let diagnostic = snapshot.diagnostic else { return false }
        return diagnostic == "controller(132)" || diagnostic == "transport(-536870207)"
    }
}

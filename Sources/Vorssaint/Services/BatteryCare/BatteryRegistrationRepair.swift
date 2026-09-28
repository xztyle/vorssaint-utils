// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import Foundation

/// Explicit operator repair after independent verification of the protected journal.
/// Normal feature removal must keep its authenticated restoration requirement.
enum BatteryRegistrationRepair {
    enum Result: String {
        case unregistered, featureEnabled, signingUnavailable, hardwareNotRestored, unregisterFailed
    }

    static func unregister(featureEnabled: Bool, hasStableSigning: Bool,
                           readHardware: () -> BatteryCommand?,
                           removeService: (@escaping (Error?) -> Void) -> Void,
                           completion: @escaping (Result) -> Void) {
        guard !featureEnabled else { completion(.featureEnabled); return }
        guard hasStableSigning else { completion(.signingUnavailable); return }
        // readState reports charge only for AC enabled and charge inhibit cleared.
        guard readHardware() == .charge else { completion(.hardwareNotRestored); return }
        removeService { error in completion(error == nil ? .unregistered : .unregisterFailed) }
    }
}

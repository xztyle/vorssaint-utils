// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import CryptoKit
import Foundation
import Security

/// Helpers trust the same signing certificate as their host, plus its exact ID.
/// An ad-hoc build cannot authenticate privileged requests.
enum AppCodeIdentity {
    static func requirement(identifier: String) -> String {
        guard identifier.range(of: "^[A-Za-z0-9.-]+$", options: .regularExpression) != nil,
              let certificate = signingCertificate() else { return "never" }
        let digest = Insecure.SHA1.hash(data: SecCertificateCopyData(certificate) as Data)
        let fingerprint = digest.map { String(format: "%02x", $0) }.joined()
        return "certificate leaf = H\"\(fingerprint)\" and identifier \"\(identifier)\""
    }

    private static func signingCertificate() -> SecCertificate? {
        var runningCode: SecCode?
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        let flags = SecCSFlags()
        guard SecCodeCopySelf(flags, &runningCode) == errSecSuccess,
              let runningCode,
              SecCodeCopyStaticCode(runningCode, flags, &staticCode) == errSecSuccess,
              let staticCode,
              SecCodeCopySigningInformation(staticCode,
                SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let values = information as? [String: Any],
              let certificates = values[kSecCodeInfoCertificates as String] as? [SecCertificate]
        else { return nil }
        return certificates.first
    }
}

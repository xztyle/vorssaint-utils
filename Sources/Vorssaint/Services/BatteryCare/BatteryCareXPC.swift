// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import Foundation

enum BatteryCareIdentifiers {
    #if VORSSAINT_DEVELOPMENT
    static let appID = "io.github.xztyle.Aster.dev"
    #else
    static let appID = "io.github.xztyle.Aster"
    #endif
    static let helperID = appID + ".battery-care"
    static let plistName = helperID + ".plist"
    static let protocolVersion = "1"
}

@objc protocol BatteryCareXPCProtocol {
    func status(withReply reply: @escaping (Data) -> Void)
    func request(_ data: Data, withReply reply: @escaping (Data) -> Void)
}

enum BatteryCareIPC {
    static func decodeRequest(_ data: Data) -> BatteryCareRequest? {
        guard data.count <= 65536,
              let request = try? JSONDecoder().decode(BatteryCareRequest.self, from: data),
              request.isValid else { return nil }
        return request
    }

    static func encode(_ response: BatteryCareResponse) -> Data {
        // All response numbers are validated before they enter the state.
        (try? JSONEncoder().encode(response)) ?? Data()
    }
}

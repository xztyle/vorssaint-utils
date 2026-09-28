// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import Foundation
import ServiceManagement

/// Signed app entry points for repeatable acceptance measurements. These use
/// the same closed, validated protocol as Settings; there is no raw key writer.
enum BatteryCareDiagnostics {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard args.contains("--battery-status") || args.contains("--battery-request")
            || args.contains("--battery-register") || args.contains("--battery-repair-registration") else { return }
        if args.contains("--battery-repair-registration") {
            guard args.count == 2 else { exit(1) }
            repairRegistration()
        }
        if args.contains("--battery-register") { register(); exit(0) }
        var request: Data?
        if let index = args.firstIndex(of: "--battery-request") {
            guard AppFeature.batteryCare.isAvailable, args.indices.contains(index + 1),
                  let data = args[index + 1].data(using: .utf8),
                  BatteryCareIPC.decodeRequest(data) != nil else {
                fputs("Enable Battery care and pass a valid bounded request.\n", stderr)
                exit(1)
            }
            request = data
        }
        connect(request: request)
    }

    private static func repairRegistration() -> Never {
        let service = SMAppService.daemon(plistName: BatteryCareIdentifiers.plistName)
        BatteryRegistrationRepair.unregister(featureEnabled: AppFeature.batteryCare.isAvailable,
            hasStableSigning: AppCodeIdentity.requirement(identifier: BatteryCareIdentifiers.helperID) != "never",
            readHardware: { try? BatteryHardware().readState() },
            removeService: { completion in
                if service.status == .notRegistered { completion(nil) }
                else { service.unregister(completionHandler: completion) }
            }, completion: { result in
                print("battery-registration-repair=\(result.rawValue)")
                // No registration, journal mutation or hardware write occurs here.
                exit(result == .unregistered ? 0 : 1)
            })
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            fputs("Battery registration repair timed out.\n", stderr)
            exit(1)
        }
        RunLoop.main.run()
        exit(1)
    }

    private static func register() {
        guard AppFeature.batteryCare.isAvailable,
              AppCodeIdentity.requirement(identifier: BatteryCareIdentifiers.helperID) != "never" else { exit(1) }
        let service = SMAppService.daemon(plistName: BatteryCareIdentifiers.plistName)
        do {
            if service.status == .notRegistered || service.status == .notFound { try service.register() }
        } catch {
            if service.status != .requiresApproval {
                fputs("\(error)\n", stderr)
                exit(1)
            }
        }
        guard service.status == .enabled || service.status == .requiresApproval else {
            fputs("Battery service did not register.\n", stderr)
            exit(1)
        }
        print("battery-service-status=\(service.status.rawValue)")
    }

    private static func connect(request: Data?) -> Never {
        let connection = NSXPCConnection(machServiceName: BatteryCareIdentifiers.helperID, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: BatteryCareXPCProtocol.self)
        connection.setCodeSigningRequirement(AppCodeIdentity.requirement(identifier: BatteryCareIdentifiers.helperID))
        connection.resume()
        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            fputs("\(error)\n", stderr)
            exit(1)
        } as? BatteryCareXPCProtocol
        let reply: (Data) -> Void = { data in
            print(String(decoding: data, as: UTF8.self))
            let response = try? JSONDecoder().decode(BatteryCareResponse.self, from: data)
            exit(response?.succeeded == true ? 0 : 1)
        }
        if let request { proxy?.request(request, withReply: reply) }
        else { proxy?.status(withReply: reply) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { exit(1) }
        withExtendedLifetime(connection) { RunLoop.main.run() }
        exit(1)
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import Darwin
import Foundation

final class BatterySession: NSObject, BatteryCareXPCProtocol {
    let controller: BatteryController
    init(_ controller: BatteryController) { self.controller = controller }
    func status(withReply reply: @escaping (Data) -> Void) { controller.status(reply) }
    func request(_ data: Data, withReply reply: @escaping (Data) -> Void) {
        controller.request(data, reply: reply)
    }
}

final class BatteryListener: NSObject, NSXPCListenerDelegate {
    let controller: BatteryController
    init(_ controller: BatteryController) { self.controller = controller }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: BatteryCareXPCProtocol.self)
        connection.exportedObject = BatterySession(controller)
        // Disconnecting the UI deliberately leaves the durable policy running.
        connection.activate()
        return true
    }
}

if CommandLine.arguments.contains("--selftest") {
    guard BatteryCarePolicy().isValid, BatteryHardware.chargeBytes(true) == [1, 0, 0, 0],
          BatteryCareIPC.decodeRequest(Data("{}".utf8)) == nil else { exit(1) }
    print("battery-care-helper: ok (no hardware writes)")
    exit(0)
}

if CommandLine.arguments.contains("--probe") {
    var snapshot = BatteryCareSnapshot()
    snapshot.sample = BatterySensor.sample()
    snapshot.fingerprint = BatteryHardware.fingerprint
    snapshot.competitors = BatteryCompetitors.running()
    do {
        let hardware = try BatteryHardware()
        snapshot.command = try hardware.readState()
        snapshot.chargeCandidate = true
        snapshot.dischargeCandidate = true
    } catch { snapshot.diagnostic = String(describing: error) }
    print(String(decoding: BatteryCareIPC.encode(.init(succeeded: true, snapshot: snapshot)), as: UTF8.self))
    exit(0)
}

guard geteuid() == 0 else { fputs("The battery daemon must run as root.\n", stderr); exit(1) }
let requirement = AppCodeIdentity.requirement(identifier: BatteryCareIdentifiers.appID)
guard requirement != "never" else { fputs("Stable signing is required.\n", stderr); exit(1) }
let journal: BatteryJournal
do { journal = try BatteryJournal() }
catch { fputs("Battery journal unavailable: \(error)\n", stderr); exit(1) }
let controller = BatteryController(journal: journal)
let sleepObserver = BatterySleepObserver(controller: controller)
guard sleepObserver.isRegistered else {
    controller.shutdown { _ in exit(1) }
    RunLoop.main.run()
    exit(1)
}
let delegate = BatteryListener(controller)
let listener = NSXPCListener(machServiceName: BatteryCareIdentifiers.helperID)
listener.setConnectionCodeSigningRequirement(requirement)
listener.delegate = delegate
listener.activate()

signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
let signals = [SIGTERM, SIGINT].map { signalNumber in
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
    source.setEventHandler { controller.shutdown { restored in if restored { exit(0) } } }
    source.resume()
    return source
}
RunLoop.main.run()

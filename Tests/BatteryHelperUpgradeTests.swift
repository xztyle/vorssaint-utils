// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import Foundation

/// Exercises the production upgrade method with local preference/XPC/service doubles.
/// No UserDefaults, launch daemon, process or hardware state is changed.
enum BatteryHelperUpgradeTests {
    static func run(_ suite: TestSuite) {
        for old in [nil, "previous"] as [String?] {
            let service = Service(old: old)
            suite.expect(service.upgradeIfNeeded() && service.removing,
                         "unknown CLI registration or older helper begins a safe upgrade")
            suite.expect(service.log.events == ["returnToSystem"], "upgrade waits for restoration before unregistering")
            service.complete?(true)
            suite.expect(service.log.events == ["returnToSystem", "unregister", "invalidate", "authorize"],
                         "successful restoration precedes unregister, connection reset and registration")
        }
        blockedRestoration(suite)
        let same = Service(old: "current")
        suite.expect(!same.upgradeIfNeeded() && same.log.events.isEmpty, "a matching helper does not restart repeatedly")
        let unknownBundle = Service(old: nil)
        unknownBundle.buildVersion = ""
        suite.expect(!unknownBundle.upgradeIfNeeded(), "missing bundle hash never initiates an unverifiable upgrade")
    }

    private static func blockedRestoration(_ suite: TestSuite) {
        for condition in ["failed", "owned", "recovery"] {
            let service = Service(old: nil)
            service.snapshot.state.ownsHardware = condition == "owned"
            service.snapshot.state.recoveryPending = condition == "recovery"
            _ = service.upgradeIfNeeded()
            service.complete?(condition != "failed")
            suite.expect(service.log.events == ["returnToSystem"] && !service.removing,
                         "upgrade retains recovery authority when restoration is \(condition)")
        }
    }

    final class Log { var events: [String] = [] }
    final class Preferences {
        var value: String?
        init(_ value: String?) { self.value = value }
        func string(forKey: String) -> String? { value }
    }
    final class Daemon {
        let log: Log
        init(_ log: Log) { self.log = log }
        func unregister() throws { log.events.append("unregister") }
    }
    final class Connection {
        let log: Log
        init(_ log: Log) { self.log = log }
        func invalidate() { log.events.append("invalidate") }
    }
    final class Service {
        let log = Log()
        let defaults: Preferences
        var daemon: Daemon
        var connection: Connection?
        var buildVersion = "current"
        var removing = false
        var snapshot = BatteryCareSnapshot()
        var complete: ((Bool) -> Void)?
        init(old: String?) {
            defaults = Preferences(old)
            daemon = Daemon(log)
            connection = Connection(log)
        }
        func send(_ request: BatteryCareRequest, completion: @escaping (Bool) -> Void) {
            log.events.append(request.kind.rawValue)
            complete = completion
        }
        func authorize() { log.events.append("authorize") }
    }
}

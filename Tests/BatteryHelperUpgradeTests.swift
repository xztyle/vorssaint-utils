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
            suite.expect(service.log.events == ["returnToSystem", "unregister"] && service.removing,
                         "upgrade waits for asynchronous unregister before registering the replacement")
            service.daemon.complete?(nil)
            suite.expect(service.log.events == ["returnToSystem", "unregister"] && service.removing,
                         "unregister completion waits for the next main-queue turn")
            service.mainQueue.run()
            suite.expect(service.log.events == ["returnToSystem", "unregister", "invalidate", "authorize"],
                         "successful restoration precedes unregister, connection reset and registration")
        }
        blockedRestoration(suite)
        unregisterFailure(suite)
        reauthorizedPolicy(suite)
        safeUpdateRemoval(suite)
        pendingUpdateRegistration(suite)
        serviceAvailability(suite)
        policyPresentation(suite)
        savedPolicyOnFailure(suite)
        let same = Service(old: "current")
        suite.expect(!same.upgradeIfNeeded() && same.log.events.isEmpty, "a matching helper does not restart repeatedly")
        let unknownBundle = Service(old: nil)
        unknownBundle.buildVersion = ""
        suite.expect(!unknownBundle.upgradeIfNeeded(), "missing bundle hash never initiates an unverifiable upgrade")
    }

    private static func serviceAvailability(_ suite: TestSuite) {
        let service = Service(old: "current")
        service.helperResponding = true; service.busy = true
        service.snapshot.reason = .holding
        service.snapshot.sample = BatteryCareTests.sample(80)
        let id = service.replyGate.begin()
        var completions: [Bool] = []
        service.failed(id: id) { completions.append($0) }
        suite.expect(!service.helperResponding && !service.busy && service.snapshot.reason == .helperUnavailable,
                     "an unreachable registered helper never retains a working protection status")
        suite.expect(service.snapshot.sample?.percent == 87 && completions == [false],
                     "a lost connection replaces stale telemetry with a local read and completes once")
        let next = service.replyGate.begin(); service.busy = true
        service.failed(id: id) { completions.append($0) }
        suite.expect(service.busy && completions == [false], "an old deadline cannot fail a newer request")
        var snapshot = BatteryCareSnapshot(); snapshot.reason = .holding
        let response = BatteryCareIPC.encode(.init(succeeded: false, snapshot: snapshot))
        service.received(response, id: next) { completions.append($0) }
        suite.expect(service.helperResponding && !service.busy && completions == [false, false],
                     "a rejected command still proves the authenticated helper is responding")
        let malformed = service.replyGate.begin()
        service.received(Data(), id: malformed, completion: nil)
        suite.expect(!service.helperResponding && service.snapshot.sample?.percent == 87,
                     "invalid helper data cannot leave stale protection or battery readings visible")
    }

    private static func policyPresentation(_ suite: TestSuite) {
        let service = Service(old: "current"); service.savedPolicy.enabled = true
        service.registered = true; service.snapshot.reason = .holding
        let editor = PolicyEditor(service)
        suite.expect(editor.statusTitle == editor.text[.serviceStopped] && !editor.canConfigure,
                     "registration alone does not present a running service or enable controls")
        service.needsApproval = true
        suite.expect(editor.statusTitle == editor.text[.approvalPending], "pending macOS approval is explicit")
        service.needsApproval = false; service.helperResponding = true
        service.recordPendingPolicyRestoration()
        var initial = BatteryCareSnapshot(); initial.helperBuild = "current"
        editor.receiveSnapshot(initial)
        suite.expect(editor.policy == service.savedPolicy && !editor.hasLoadedDaemonPolicy && !editor.canConfigure,
                     "a fresh helper's default policy cannot turn off saved intent during restoration")
        service.defaults.removeObject(forKey: DefaultsKey.batteryCarePendingUpgradeActivation)
        initial.state.policy = service.savedPolicy; editor.receiveSnapshot(initial)
        suite.expect(editor.hasLoadedDaemonPolicy && editor.canConfigure && editor.policy.enabled,
                     "confirmed restoration adopts the daemon policy and enables controls")
        editor.policy.upper = 85; initial.state.policy.upper = 82; editor.receiveSnapshot(initial)
        suite.expect(editor.policy.upper == 85, "later daemon refreshes preserve unsaved editor changes")
    }

    private static func savedPolicyOnFailure(_ suite: TestSuite) {
        let service = Service(old: "current"); service.savedPolicy.enabled = true
        let editor = PolicyEditor(service); editor.policy.upper = 85
        editor.savePolicy(); service.complete?(false)
        suite.expect(editor.policy == service.savedPolicy && editor.policy.enabled,
                     "a failed save restores saved enabled intent instead of an inactive stale daemon policy")
        for language in AppLanguage.allCases {
            let text = FeatureStrings.batteryCare(language)
            let message = String(format: text[.policyInactive], 75, 80)
            suite.expect(!message.contains("%d") && message.contains("75") && message.contains("80"),
                         "every inactive-policy translation includes the saved range")
        }
    }

    private static func pendingUpdateRegistration(_ suite: TestSuite) {
        let pending = Service(old: nil); pending.savedPolicy.enabled = true
        pending.recordPendingPolicyRestoration(); pending.log.events = []
        pending.syncWithPreferences()
        suite.expect(pending.log.events == ["authorize", "updateTimer"],
                     "the next app launch registers a safely released service and restores saved intent")
        let ordinary = Service(old: nil)
        ordinary.syncWithPreferences()
        suite.expect(ordinary.log.events == ["updateTimer"],
                     "an ordinary first launch does not silently install a privileged service")
        let disabled = Service(old: nil); disabled.registered = true; disabled.featureEnabled = false
        disabled.syncWithPreferences()
        suite.expect(disabled.log.events == ["removeHelper", "updateTimer"],
                     "a disabled battery feature follows removal rather than update registration")
        pending.log.events = []; pending.registered = true; pending.syncWithPreferences()
        suite.expect(pending.log.events == ["refresh", "updateTimer"],
                     "an already registered replacement refreshes without another authorization cycle")
        let cancelled = Service(old: nil)
        cancelled.defaults.set(true, forKey: DefaultsKey.batteryCarePendingUpgradeActivation)
        cancelled.syncWithPreferences()
        suite.expect(cancelled.log.events == ["updateTimer"],
                     "a disabled saved policy cannot trigger automatic registration through an old pending flag")
    }

    private static func safeUpdateRemoval(_ suite: TestSuite) {
        for failure in ["none", "request", "owned", "recovery", "unregister", "xpc"] {
            let service = RemovalFixture.SMAppService()
            service.failure = failure
            RemovalFixture.SMAppService.current = service
            suite.expect(RemovalFixture.detachForRemoval() == (failure == "none"),
                         "production update removal succeeds only after restoration and unregister: \(failure)")
            let mayUnregister = failure == "none" || failure == "unregister"
            suite.expect(service.events.contains("unregister") == mayUnregister,
                         "failed or incomplete hardware release never removes recovery authority: \(failure)")
            suite.expect(service.events.last == "invalidate", "update removal closes its authenticated connection")
        }
        for status in [RemovalFixture.SMAppService.Status.notRegistered, .notFound, .requiresApproval] {
            let service = RemovalFixture.SMAppService(); service.status = status
            RemovalFixture.SMAppService.current = service
            suite.expect(RemovalFixture.detachForRemoval() == (status != .requiresApproval)
                && service.events.isEmpty, "unregistered services need no writes; approval-pending service is not bypassed")
        }
    }

    private static func reauthorizedPolicy(_ suite: TestSuite) {
        let service = Service(old: nil)
        service.savedPolicy.enabled = true
        service.recordAuthorizedBuild()
        suite.expect(service.defaults.string(forKey: DefaultsKey.batteryCareHelperVersion) == "current",
                     "reauthorization records the current helper even after removal cleared its version")
        suite.expect(service.defaults.bool(forKey: DefaultsKey.batteryCarePendingUpgradeActivation),
                     "reauthorization retains a durable request to restore the saved enabled policy")
        suite.expect(service.log.events == ["updateTimer"],
                     "policy restoration continues polling after its settings window closes")
        let disabled = Service(old: nil)
        disabled.recordAuthorizedBuild()
        suite.expect(!disabled.defaults.bool(forKey: DefaultsKey.batteryCarePendingUpgradeActivation)
            && disabled.log.events.isEmpty, "a disabled saved policy is not silently activated by registration")
    }

    private static func unregisterFailure(_ suite: TestSuite) {
        let service = Service(old: nil)
        _ = service.upgradeIfNeeded()
        service.complete?(true)
        service.daemon.complete?(NSError(domain: "fixture", code: 1))
        service.mainQueue.run()
        suite.expect(service.log.events == ["returnToSystem", "unregister"] && !service.removing
            && service.snapshot.reason == .helperUnavailable,
                     "failed unregister never registers over the previous service")
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
        private var values: [String: Any] = [:]
        init(_ value: String?) { values[DefaultsKey.batteryCareHelperVersion] = value }
        func string(forKey key: String) -> String? { values[key] as? String }
        func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
        func set(_ value: Any, forKey key: String) { values[key] = value }
        func removeObject(forKey key: String) { values.removeValue(forKey: key) }
    }
    final class Daemon {
        let log: Log
        var complete: ((Error?) -> Void)?
        init(_ log: Log) { self.log = log }
        func unregister(completionHandler: @escaping (Error?) -> Void) {
            log.events.append("unregister")
            complete = completionHandler
        }
    }
    final class MainQueue {
        var pending: (() -> Void)?
        func async(execute: @escaping () -> Void) { pending = execute }
        func run() { let work = pending; pending = nil; work?() }
    }
    final class Connection {
        let log: Log
        init(_ log: Log) { self.log = log }
        func invalidate() { log.events.append("invalidate") }
    }
    final class Service {
        let log = Log()
        let mainQueue = MainQueue()
        let defaults: Preferences
        var daemon: Daemon
        var connection: Connection?
        var buildVersion = "current"
        var removing = false
        var snapshot = BatteryCareSnapshot()
        var savedPolicy = BatteryCarePolicy()
        var registered = false
        var needsApproval = false
        var helperResponding = false
        var busy = false
        var replyGate = BatteryReplyGate()
        var featureEnabled = true
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
        func registerReplacementAfterRemoval() { authorize() }
        func updateTimer() { log.events.append("updateTimer") }
        func refreshRegistration() {}
        func refresh() { log.events.append("refresh") }
        func removeHelper() { log.events.append("removeHelper") }
        func sampleBattery() -> BatterySample { BatteryCareTests.sample(87, charging: true) }
        func apply(_ policy: BatteryCarePolicy, completion: @escaping (Bool) -> Void) { complete = completion }
    }

    final class PolicyEditor {
        let service: Service
        let text = FeatureStrings.batteryCare(.enUS)
        var snapshot: BatteryCareSnapshot { service.snapshot }
        var policy: BatteryCarePolicy
        var lastDaemonPolicy: BatteryCarePolicy
        var hasLoadedDaemonPolicy = false
        init(_ service: Service) {
            self.service = service
            policy = service.savedPolicy
            lastDaemonPolicy = policy
        }
    }

    enum RemovalFixture {
        final class SMAppService {
            enum Status { case enabled, notRegistered, notFound, requiresApproval }
            static var current = SMAppService()
            var status = Status.enabled
            var failure = "none"
            var events: [String] = []
            static func daemon(plistName: String) -> SMAppService { current }
            func unregister() throws {
                events.append("unregister")
                if failure == "unregister" { throw NSError(domain: "fixture", code: 1) }
            }
        }
        static func removalConnection() -> Connection { Connection(SMAppService.current) }
        final class Connection {
            let service: SMAppService
            init(_ service: SMAppService) { self.service = service }
            func invalidate() { service.events.append("invalidate") }
            func remoteObjectProxyWithErrorHandler(_ handler: @escaping (Error) -> Void) -> Any {
                if service.failure == "xpc" {
                    handler(NSError(domain: "fixture", code: 1))
                    return NSObject()
                }
                return Proxy(service)
            }
        }
        final class Proxy: NSObject, BatteryCareXPCProtocol {
            let service: SMAppService
            init(_ service: SMAppService) { self.service = service }
            func status(withReply reply: @escaping (Data) -> Void) { reply(Data()) }
            func request(_ data: Data, withReply reply: @escaping (Data) -> Void) {
                service.events.append(BatteryCareIPC.decodeRequest(data)?.kind.rawValue ?? "invalid")
                var snapshot = BatteryCareSnapshot()
                snapshot.state.ownsHardware = service.failure == "owned"
                snapshot.state.recoveryPending = service.failure == "recovery"
                reply(BatteryCareIPC.encode(.init(succeeded: service.failure != "request", snapshot: snapshot)))
            }
        }
    }
}

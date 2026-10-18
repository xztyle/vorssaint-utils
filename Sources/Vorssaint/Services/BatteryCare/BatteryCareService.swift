// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import AppKit
import ServiceManagement

final class BatteryCareService: ObservableObject {
    static let shared = BatteryCareService()
    @Published private(set) var snapshot = BatteryCareSnapshot()
    @Published private(set) var registered = false
    @Published private(set) var needsApproval = false
    @Published private(set) var helperResponding = false
    @Published private(set) var busy = false
    private var connection: NSXPCConnection?
    private var timer: Timer?
    private var panelVisible = false
    private var replyGate = BatteryReplyGate()
    private var removing = false

    private var daemon: SMAppService { .daemon(plistName: BatteryCareIdentifiers.plistName) }
    private var buildVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "AsterBatteryCareHelperVersion") as? String ?? ""
    }

    var savedPolicy: BatteryCarePolicy {
        BatteryCarePreferences.decode(UserDefaults.standard.string(forKey: DefaultsKey.batteryCarePolicy))
            ?? BatteryCarePolicy()
    }

    var restoringPolicy: Bool {
        savedPolicy.enabled && UserDefaults.standard.bool(forKey: DefaultsKey.batteryCarePendingUpgradeActivation)
    }

    func syncWithPreferences() {
        refreshRegistration()
        if !AppFeature.batteryCare.isAvailable {
            if registered { removeHelper() }
            updateTimer()
            return
        }
        if registered { refresh() }
        else if UserDefaults.standard.bool(forKey: DefaultsKey.batteryCarePendingUpgradeActivation),
                savedPolicy.enabled { authorize() }
        updateTimer()
    }

    func panelDidAppear() {
        guard AppFeature.batteryCare.isAvailable else { return }
        panelVisible = true
        refresh()
        updateTimer()
    }

    func panelDidDisappear() { panelVisible = false; updateTimer() }

    func openBackgroundSettings() { SMAppService.openSystemSettingsLoginItems() }

    private func updateTimer() {
        let pending = UserDefaults.standard.bool(forKey: DefaultsKey.batteryCarePendingUpgradeActivation)
        let shouldRun = AppFeature.batteryCare.isAvailable && (panelVisible || pending)
        if shouldRun && timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.refresh() }
        } else if !shouldRun { timer?.invalidate(); timer = nil }
    }

    func authorize() {
        guard AppFeature.batteryCare.isAvailable else { return }
        guard AppCodeIdentity.requirement(identifier: BatteryCareIdentifiers.helperID) != "never" else {
            snapshot.reason = .helperUnavailable
            return
        }
        do {
            // A bundled daemon can report notFound before its first registration.
            if daemon.status == .notRegistered || daemon.status == .notFound { try daemon.register() }
            refreshRegistration()
            // Approval may happen after Aster quits. Record the replacement now
            // so the next launch does not unregister it a second time.
            if registered || needsApproval { recordAuthorizedBuild() }
            if needsApproval { SMAppService.openSystemSettingsLoginItems() }
            if registered {
                refresh()
            }
        } catch {
            refreshRegistration()
            if needsApproval { SMAppService.openSystemSettingsLoginItems() }
            else { snapshot.reason = .helperUnavailable; snapshot.diagnostic = String(describing: error) }
        }
    }

    func recordAuthorizedBuild() {
        UserDefaults.standard.set(buildVersion, forKey: DefaultsKey.batteryCareHelperVersion)
        recordPendingPolicyRestoration()
    }

    func recordPendingPolicyRestoration() {
        if savedPolicy.enabled {
            UserDefaults.standard.set(true, forKey: DefaultsKey.batteryCarePendingUpgradeActivation)
            updateTimer()
        }
    }

    func refresh() {
        guard !busy, !removing else { return }
        refreshRegistration()
        if registered {
            if UserDefaults.standard.string(forKey: DefaultsKey.batteryCareHelperVersion) != buildVersion,
               savedPolicy.enabled {
                UserDefaults.standard.set(true, forKey: DefaultsKey.batteryCarePendingUpgradeActivation)
                updateTimer()
            }
            if upgradeIfNeeded() { return }
            send(nil) { [weak self] success in
                guard success else { return }
                self?.restorePolicyAfterUpgrade()
            }
        } else { snapshot.sample = BatterySensor.sample() }
    }

    private func restorePolicyAfterUpgrade() {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.batteryCarePendingUpgradeActivation) else { return }
        let policy = savedPolicy
        guard policy.enabled else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.batteryCarePendingUpgradeActivation)
            updateTimer()
            return
        }
        if snapshot.state.policy == policy {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.batteryCarePendingUpgradeActivation)
            updateTimer()
            return
        }
        apply(policy) { success in
            if success {
                UserDefaults.standard.removeObject(forKey: DefaultsKey.batteryCarePendingUpgradeActivation)
                self.updateTimer()
            }
        }
    }

    private func refreshRegistration() {
        registered = daemon.status == .enabled
        needsApproval = daemon.status == .requiresApproval
        if !registered { helperResponding = false }
    }

    func apply(_ policy: BatteryCarePolicy, completion: ((Bool) -> Void)? = nil) {
        guard policy.isValid else {
            snapshot.reason = .invalidRequest
            completion?(false)
            return
        }
        guard registered, !busy else { completion?(false); return }
        send(.init(kind: .configure, policy: policy)) { succeeded in
            if succeeded {
                UserDefaults.standard.set(BatteryCarePreferences.encode(policy),
                                          forKey: DefaultsKey.batteryCarePolicy)
            }
            completion?(succeeded)
        }
    }

    func perform(_ kind: BatteryRequestKind, policy: BatteryCarePolicy? = nil, target: Int? = nil) {
        guard AppFeature.batteryCare.isAvailable || kind == .returnToSystem else { return }
        guard registered, !busy else { return }
        send(.init(kind: kind, policy: policy, target: target)) { success in
            guard success, kind == .returnToSystem else { return }
            var policy = self.savedPolicy
            policy.enabled = false
            UserDefaults.standard.set(BatteryCarePreferences.encode(policy),
                                      forKey: DefaultsKey.batteryCarePolicy)
            UserDefaults.standard.removeObject(forKey: DefaultsKey.batteryCarePendingUpgradeActivation)
            self.updateTimer()
        }
    }

    private func proxy(onError: @escaping () -> Void) -> BatteryCareXPCProtocol? {
        if connection == nil {
            let connection = NSXPCConnection(machServiceName: BatteryCareIdentifiers.helperID, options: .privileged)
            connection.remoteObjectInterface = NSXPCInterface(with: BatteryCareXPCProtocol.self)
            connection.setCodeSigningRequirement(AppCodeIdentity.requirement(identifier: BatteryCareIdentifiers.helperID))
            connection.invalidationHandler = { [weak self] in DispatchQueue.main.async { self?.connection = nil } }
            connection.resume()
            self.connection = connection
        }
        return connection?.remoteObjectProxyWithErrorHandler { _ in
            DispatchQueue.main.async(execute: onError)
        } as? BatteryCareXPCProtocol
    }

    private func send(_ request: BatteryCareRequest?, completion: ((Bool) -> Void)? = nil) {
        busy = true
        let id = replyGate.begin()
        let failed = { [weak self] in self?.failed(id: id, completion: completion) }
        guard let proxy = proxy(onError: { failed() }) else { failed(); return }
        let reply: (Data) -> Void = { [weak self] data in
            DispatchQueue.main.async { self?.received(data, id: id, completion: completion) }
        }
        if let request, let data = try? JSONEncoder().encode(request) { proxy.request(data, withReply: reply) }
        else { proxy.status(withReply: reply) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            self?.failed(id: id, completion: completion)
        }
    }

    private func failed(id: UUID, completion: ((Bool) -> Void)?) {
        guard replyGate.consume(id) else { return }
        busy = false
        markUnavailable()
        completion?(false)
    }

    private func markUnavailable() {
        helperResponding = false
        snapshot.reason = .helperUnavailable
        snapshot.sample = BatterySensor.sample()
    }

    private func received(_ data: Data, id: UUID, completion: ((Bool) -> Void)?) {
        guard replyGate.consume(id) else { return }
        busy = false
        guard let response = try? JSONDecoder().decode(BatteryCareResponse.self, from: data) else {
            markUnavailable()
            completion?(false)
            return
        }
        helperResponding = true
        snapshot = response.snapshot
        completion?(response.succeeded)
    }

    private func upgradeIfNeeded() -> Bool {
        let old = UserDefaults.standard.string(forKey: DefaultsKey.batteryCareHelperVersion)
        guard !buildVersion.isEmpty, old != buildVersion else { return false }
        removing = true
        send(.init(kind: .returnToSystem)) { success in
            guard success, !self.snapshot.state.ownsHardware, !self.snapshot.state.recoveryPending else {
                self.removing = false
                return
            }
            // Synchronous unregister returns before launchd reaps the old service.
            self.daemon.unregister { error in
                DispatchQueue.main.async {
                    self.removing = false
                    guard error == nil else { self.snapshot.reason = .helperUnavailable; return }
                    self.connection?.invalidate()
                    self.connection = nil
                    self.registerReplacementAfterRemoval()
                }
            }
        }
        return true
    }

    private func registerReplacementAfterRemoval() {
        // launchd can still hold the old service immediately after the
        // unregister completion. Give it time to release that registration.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.authorize() }
    }

    func removeHelper() {
        guard !removing else { return }
        removing = true
        send(.init(kind: .returnToSystem)) { success in
            self.removing = false
            guard success, !self.snapshot.state.ownsHardware, !self.snapshot.state.recoveryPending else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    if !AppFeature.batteryCare.isAvailable { self.removeHelper() }
                }
                return
            }
            do {
                try self.daemon.unregister()
                self.connection?.invalidate()
                self.connection = nil
                UserDefaults.standard.removeObject(forKey: DefaultsKey.batteryCareHelperVersion)
                UserDefaults.standard.removeObject(forKey: DefaultsKey.batteryCarePendingUpgradeActivation)
                self.updateTimer()
                self.refreshRegistration()
            } catch { self.snapshot.reason = .helperUnavailable }
        }
    }

    /// Called from the existing uninstall worker, never the main thread.
    static func detachForRemoval() -> Bool {
        let daemon = SMAppService.daemon(plistName: BatteryCareIdentifiers.plistName)
        if daemon.status == .notRegistered || daemon.status == .notFound { return true }
        guard daemon.status == .enabled else { return false }
        let semaphore = DispatchSemaphore(value: 0)
        var restored = false
        let connection = removalConnection()
        defer { connection.invalidate() }
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in semaphore.signal() } as? BatteryCareXPCProtocol
        let data = try! JSONEncoder().encode(BatteryCareRequest(kind: .returnToSystem))
        proxy?.request(data) { data in
            let response = try? JSONDecoder().decode(BatteryCareResponse.self, from: data)
            restored = response?.succeeded == true && response?.snapshot.state.recoveryPending == false
                && response?.snapshot.state.ownsHardware == false
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 15) == .success, restored else { return false }
        do { try daemon.unregister(); return true } catch { return false }
    }

    private static func removalConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(machServiceName: BatteryCareIdentifiers.helperID, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: BatteryCareXPCProtocol.self)
        connection.setCodeSigningRequirement(AppCodeIdentity.requirement(identifier: BatteryCareIdentifiers.helperID))
        connection.resume()
        return connection
    }
}

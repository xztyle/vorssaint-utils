// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import AppKit
import ServiceManagement

final class BatteryCareService: ObservableObject {
    static let shared = BatteryCareService()
    @Published private(set) var snapshot = BatteryCareSnapshot()
    @Published private(set) var registered = false
    @Published private(set) var needsApproval = false
    @Published private(set) var busy = false
    private var connection: NSXPCConnection?
    private var timer: Timer?
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

    func syncWithPreferences() {
        refreshRegistration()
        if !AppFeature.batteryCare.isAvailable {
            if registered { removeHelper() }
            return
        }
        if registered { refresh() }
    }

    func panelDidAppear() {
        guard AppFeature.batteryCare.isAvailable else { return }
        refresh()
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.refresh() }
        }
    }

    func panelDidDisappear() { timer?.invalidate(); timer = nil }

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
            if needsApproval { SMAppService.openSystemSettingsLoginItems() }
            if registered {
                UserDefaults.standard.set(buildVersion, forKey: DefaultsKey.batteryCareHelperVersion)
                refresh()
            }
        } catch {
            refreshRegistration()
            if needsApproval { SMAppService.openSystemSettingsLoginItems() }
            else { snapshot.reason = .helperUnavailable; snapshot.diagnostic = String(describing: error) }
        }
    }

    func refresh() {
        guard !busy, !removing else { return }
        refreshRegistration()
        if registered {
            if upgradeIfNeeded() { return }
            send(nil)
        } else { snapshot.sample = BatterySensor.sample() }
    }

    private func refreshRegistration() {
        registered = daemon.status == .enabled
        needsApproval = daemon.status == .requiresApproval
    }

    func apply(_ policy: BatteryCarePolicy) {
        guard policy.isValid else { snapshot.reason = .invalidRequest; return }
        UserDefaults.standard.set(BatteryCarePreferences.encode(policy), forKey: DefaultsKey.batteryCarePolicy)
        perform(.configure, policy: policy)
    }

    func perform(_ kind: BatteryRequestKind, policy: BatteryCarePolicy? = nil, target: Int? = nil) {
        guard AppFeature.batteryCare.isAvailable || kind == .returnToSystem else { return }
        guard registered, !busy else { return }
        send(.init(kind: kind, policy: policy, target: target))
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
        snapshot.reason = .helperUnavailable
        completion?(false)
    }

    private func received(_ data: Data, id: UUID, completion: ((Bool) -> Void)?) {
        guard replyGate.consume(id) else { return }
        busy = false
        guard let response = try? JSONDecoder().decode(BatteryCareResponse.self, from: data) else {
            snapshot.reason = .helperUnavailable
            completion?(false)
            return
        }
        snapshot = response.snapshot
        completion?(response.succeeded)
    }

    private func upgradeIfNeeded() -> Bool {
        let old = UserDefaults.standard.string(forKey: DefaultsKey.batteryCareHelperVersion)
        guard old != nil, old != buildVersion else { return false }
        removing = true
        send(.init(kind: .returnToSystem)) { success in
            guard success, !self.snapshot.state.recoveryPending else { self.removing = false; return }
            do {
                try self.daemon.unregister()
                self.connection?.invalidate()
                self.connection = nil
                self.removing = false
                self.authorize()
            } catch { self.removing = false; self.snapshot.reason = .helperUnavailable }
        }
        return true
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

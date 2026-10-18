// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import AppKit

@MainActor
final class MenuBarNativeLayoutCoordinator {
    private struct Receipt: Codable { let before: Data; let written: Data; let order: [MenuBarItemIdentity] }
    private static let receiptKey = DefaultsKey.menuBarNativeTransaction
    private let access = MenuBarNativeLayoutAccess.shared
    private let defaults = UserDefaults.standard
    var requestRefresh: () -> Void = {}
    var recoveryNeeded: Bool { defaults.data(forKey: Self.receiptKey) != nil }

    func key(_ item: ManagedMenuBarItem, in document: MenuBarNativeLayoutDocument) -> String? {
        guard item.identityState == .stable else { return nil }
        return MenuBarNativeKeyPolicy.key(bundle: item.bundleIdentifier, title: item.id.title,
            name: item.sourceName, positions: document.positions)
    }

    func move(_ identity: MenuBarItemIdentity, before target: MenuBarItemIdentity?) async throws {
        guard !recoveryNeeded else { throw MenuBarItemMoveError.verificationFailed }
        let snapshot = await MenuBarNativeAXProvider.snapshot(includingOwn: true)
        guard snapshot.enumerationSucceeded, let source = snapshot.items.first(where: { $0.id == identity }),
              !source.isProtected, source.bundleIdentifier != Bundle.main.bundleIdentifier else {
            throw MenuBarItemMoveError.itemNotMovable
        }
        let document = try access.read()
        let changes = try changes(for: source, before: target, document: document, items: snapshot.items)
        guard !changes.isEmpty else { return }
        try await transact(changes, document: document, items: snapshot.items)
    }

    private func changes(for source: ManagedMenuBarItem, before target: MenuBarItemIdentity?,
                         document: MenuBarNativeLayoutDocument, items: [ManagedMenuBarItem]) throws -> [String: Double] {
        let keys = items.map { key($0, in: document) }
        guard Set(keys.compactMap { $0 }).count == keys.compactMap({ $0 }).count else {
            throw MenuBarItemMoveError.itemNotMovable
        }
        guard let sourceKey = key(source, in: document) else { throw MenuBarItemMoveError.itemUnavailable }
        let targetKey = target.flatMap { id in items.first { $0.id == id }.flatMap { key($0, in: document) } }
        guard target == nil || targetKey != nil else { throw MenuBarItemMoveError.itemUnavailable }
        let pinned = Set(items.filter { $0.isProtected || $0.bundleIdentifier == Bundle.main.bundleIdentifier }
            .compactMap { key($0, in: document) })
        guard let changes = MenuBarNativeKeyPolicy.move(source: sourceKey, before: targetKey,
            current: keys, pinned: pinned, positions: document.positions) else { throw MenuBarItemMoveError.itemNotMovable }
        return changes
    }

    private func transact(_ changes: [String: Double], document: MenuBarNativeLayoutDocument,
                          items: [ManagedMenuBarItem]) async throws {
        let expected = expectedOrder(items, document: document, changes: changes)
        let receipt = Receipt(before: document.data, written: try document.replacing(changes), order: items.map(\.id))
        defaults.set(try JSONEncoder().encode(receipt), forKey: Self.receiptKey)
        do {
            _ = try access.writeData(receipt.written, basedOn: document)
            requestRefresh()
            guard await verify(expected) else { throw MenuBarItemMoveError.verificationFailed }
            defaults.removeObject(forKey: Self.receiptKey)
        } catch {
            _ = try? await recover()
            throw error
        }
    }

    private func expectedOrder(_ items: [ManagedMenuBarItem], document: MenuBarNativeLayoutDocument,
                               changes: [String: Double]) -> [MenuBarItemIdentity] {
        let keyed = Dictionary(grouping: items.compactMap { item in key(item, in: document).map { ($0, item.id) } }, by: { $0.0 })
        return items.map { item in
            guard let original = key(item, in: document), changes[original] != nil,
                  let weight = document.positions[original], let replacement = changes.first(where: { $0.value == weight }),
                  keyed[replacement.key]?.count == 1 else { return item.id }
            return keyed[replacement.key]![0].1
        }
    }

    private func verify(_ expected: [MenuBarItemIdentity]) async -> Bool {
        let deadline = Date().addingTimeInterval(6)
        return await verify(expected, until: deadline, recovery: false)
    }

    private func verify(_ expected: [MenuBarItemIdentity], until deadline: Date, recovery: Bool) async -> Bool {
        while Date() < deadline {
            if !recovery && Task.isCancelled { return false }
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return false }
            let snapshot = await MenuBarNativeAXProvider.snapshot(includingOwn: true)
            guard snapshot.enumerationSucceeded else { continue }
            let ids = snapshot.items.map(\.id)
            if !recovery && ids == expected { return true }
            if recovery {
                let original = Set(expected), current = Set(ids)
                if ids.filter({ original.contains($0) }) == expected.filter({ current.contains($0) }) { return true }
            }
        }
        return false
    }

    @discardableResult
    func recover() async throws -> Bool {
        guard let data = defaults.data(forKey: Self.receiptKey) else { return true }
        guard data.count <= 6_291_456 else { throw MenuBarItemMoveError.verificationFailed }
        let receipt = try JSONDecoder().decode(Receipt.self, from: data)
        let current = try access.read()
        let original = try MenuBarNativeLayoutDocument(data: receipt.before)
        if current.positions != original.positions {
            let written = try MenuBarNativeLayoutDocument(data: receipt.written)
            guard MenuBarNativePreferenceStore.equal(current.root, written.root) else { throw MenuBarItemMoveError.verificationFailed }
            _ = try access.writeData(receipt.before, basedOn: current)
        }
        requestRefresh()
        guard try access.read().positions == original.positions,
              await verifyRecovery(receipt.order) else { throw MenuBarItemMoveError.verificationFailed }
        defaults.removeObject(forKey: Self.receiptKey)
        return true
    }

    private func verifyRecovery(_ expected: [MenuBarItemIdentity]) async -> Bool {
        // Recovery must finish even if the move was cancelled by sleep or quit.
        let task = Task { await verify(expected, until: Date().addingTimeInterval(6), recovery: true) }
        return await task.value
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors
// MenuBarClientCore visibility follows Thaw's GPLv3 preview.1 approach.

import AppKit
import os

@MainActor
final class MenuBarNativeVisibility {
    private var handle: UnsafeMutableRawPointer?
    private var task: Task<Void, Never>?
    private var generation = 0
    private var allowed: Set<String> = []
    private var failedConfiguration: Set<String>?
    private(set) var concealed: Set<String> = []
    var available: Bool { AsterMenuVisibilityAvailable() }

    func apply(hidden: Set<MenuBarItemIdentity>, items: [ManagedMenuBarItem], failure: @escaping () -> Void) {
        let bundles = Set(hidden.map(\.bundleIdentifier))
        let visible = Set(items.filter { !hidden.contains($0.id) }.map(\.bundleIdentifier))
        guard bundles.isDisjoint(with: visible), !bundles.contains(where: { $0.hasPrefix("com.apple.") }),
              !bundles.contains(Bundle.main.bundleIdentifier ?? "io.github.xztyle.Aster") else { reset(); failure(); return }
        guard !bundles.isEmpty else { reset(); return }
        let desired = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)).subtracting(bundles)
            .union([Bundle.main.bundleIdentifier ?? "io.github.xztyle.Aster"])
        guard bundles != concealed || !desired.isSubset(of: allowed) || handle == nil && task == nil else { return }
        guard available, desired != failedConfiguration else { reset(); failure(); return }
        reset(); let token = generation
        concealed = bundles; allowed = desired
        task = Task { [weak self] in await self?.activate(desired, items: items, token: token, failure: failure) }
    }

    private func activate(_ desired: Set<String>, items: [ManagedMenuBarItem], token: Int,
                          failure: @escaping () -> Void) async {
        guard token == generation, !Task.isCancelled else { return }
        let before = await MenuBarNativeAXProvider.snapshot(includingOwn: true)
        let visible = MenuBarNativeVisibilityExpectation(items.filter { !concealed.contains($0.bundleIdentifier) })
        guard token == generation, !Task.isCancelled else { return }
        guard before.enumerationSucceeded, visible.matches(before.items) else {
            Logger(subsystem: "io.github.xztyle.Aster", category: "MenuBarNativeVisibility").error("Visible inventory changed before hiding")
            fail(desired, token: token, failure: failure); return
        }
        let expected = MenuBarNativeVisibilityExpectation(before.items.filter { !concealed.contains($0.bundleIdentifier) })
        handle = AsterMenuVisibilityActivate(desired.sorted(), (0...8).map { NSNumber(value: $0) }) { [weak self] in
            MainActor.assumeIsolated { self?.fail(desired, token: token, failure: failure) }
        }
        guard handle != nil else {
            Logger(subsystem: "io.github.xztyle.Aster", category: "MenuBarNativeVisibility").error("Native visibility assertion unavailable")
            fail(desired, token: token, failure: failure); return
        }
        await verify(expected, desired: desired, token: token, failure: failure)
    }

    private func verify(_ expected: MenuBarNativeVisibilityExpectation, desired: Set<String>, token: Int,
                        failure: @escaping () -> Void) async {
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline {
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            let current = await MenuBarNativeAXProvider.snapshot(includingOwn: true)
            guard token == generation, !Task.isCancelled else { return }
            if current.enumerationSucceeded, expected.matches(current.items),
               current.items.allSatisfy({ !concealed.contains($0.bundleIdentifier) }) { task = nil; return }
        }
        Logger(subsystem: "io.github.xztyle.Aster", category: "MenuBarNativeVisibility").error("Native visibility did not preserve the requested inventory")
        fail(desired, token: token, failure: failure)
    }

    private func fail(_ configuration: Set<String>, token: Int, failure: () -> Void) {
        guard generation == token else { return }
        reset(); failedConfiguration = configuration; failure()
    }

    func retry() { failedConfiguration = nil }

    func reset() {
        generation += 1; task?.cancel(); task = nil
        if let handle { AsterMenuVisibilityInvalidate(handle) }
        handle = nil; concealed = []; allowed = []
    }
}

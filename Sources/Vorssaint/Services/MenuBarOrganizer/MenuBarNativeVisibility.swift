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
    private static let log = Logger(subsystem: "io.github.xztyle.Aster", category: "MenuBarNativeVisibility")
    var available: Bool { AsterMenuVisibilityAvailable() }

    func apply(hidden: Set<MenuBarItemIdentity>, items: [ManagedMenuBarItem], failure: @escaping () -> Void) {
        let bundles = Set(hidden.map(\.bundleIdentifier))
        let visible = Set(items.filter { !hidden.contains($0.id) }.map(\.bundleIdentifier))
        guard bundles.isDisjoint(with: visible), !bundles.contains(where: { $0.hasPrefix("com.apple.") }),
              !bundles.contains(Bundle.main.bundleIdentifier ?? "io.github.xztyle.Aster") else {
            Self.log.notice("Hiding refused: an app has both hidden and visible icons, or is a system or Aster icon")
            reset(); failure(); return
        }
        guard !bundles.isEmpty else { reset(); return }
        let desired = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)).subtracting(bundles)
            .union([Bundle.main.bundleIdentifier ?? "io.github.xztyle.Aster"])
        guard bundles != concealed || !desired.isSubset(of: allowed) || handle == nil && task == nil else { return }
        guard available, desired != failedConfiguration else {
            Self.log.notice("Hiding unavailable: service \(self.available), repeated failure \(desired == self.failedConfiguration)")
            reset(); failure(); return
        }
        Self.log.notice("Hiding \(bundles.sorted(), privacy: .public)")
        // Keep the current pass until its replacement is active, so a newly
        // launched app never makes every hidden icon flash back.
        generation += 1; task?.cancel(); task = nil; let token = generation
        concealed = bundles; allowed = desired
        task = Task { [weak self] in await self?.activate(desired, token: token, failure: failure) }
    }

    private func activate(_ desired: Set<String>, token: Int,
                          failure: @escaping () -> Void) async {
        // No Accessibility pre-check: reading every icon took seconds with a
        // busy menu bar, and a click during that gap undid the hide.
        guard token == generation, !Task.isCancelled else { return }
        let previous = handle
        handle = AsterMenuVisibilityActivate(desired.sorted(), (0...8).map { NSNumber(value: $0) }) { [weak self] in
            MainActor.assumeIsolated { self?.fail(desired, token: token, failure: failure) }
        }
        if let previous { AsterMenuVisibilityInvalidate(previous) }
        guard handle != nil else {
            Logger(subsystem: "io.github.xztyle.Aster", category: "MenuBarNativeVisibility").error("Native visibility assertion unavailable")
            fail(desired, token: token, failure: failure); return
        }
        // macOS reports a refusal through the completion handler. The visible
        // inventory is not a usable check: macOS 27 also hides some unrelated
        // publishers (iStat Menus, Setapp, Now Playing) while a pass is active.
        Self.log.notice("Hiding active")
        task = nil
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

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors
import AppKit

/// Command-line check of the macOS 27 reorder path:
/// `--menu-bar-move SOURCE TARGET` moves SOURCE immediately left of TARGET.
/// Each name matches an icon's bundle identifier, title or display name.
/// It posts a visible Command-drag, so it changes the real menu bar order.
enum MenuBarMoveProbe {
    static func runIfRequestedAndExit() {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--menu-bar-move") else { return }
        guard args.count == index + 3 else {
            fputs("Usage: --menu-bar-move SOURCE TARGET\n", stderr)
            exit(1)
        }
        Task { @MainActor in exit(await run(source: args[index + 1], target: args[index + 2])) }
        RunLoop.main.run()
        exit(3)
    }

    @MainActor
    private static func run(source: String, target: String) async -> Int32 {
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27, AXIsProcessTrusted() else {
            fputs("Requires macOS 27 and Accessibility access.\n", stderr)
            return 1
        }
        let snapshot = await MenuBarNativeAXProvider.snapshot(includingOwn: true)
        guard let from = find(source, in: snapshot.items), let to = find(target, in: snapshot.items) else {
            fputs("Icon not found, or the name matches more than one icon.\n", stderr)
            return 2
        }
        do {
            try await MenuBarNativeDragMover().move(from.id, before: to.id)
            print("moved=\(from.displayName) before=\(to.displayName)")
            return 0
        } catch {
            print("failed=\(error)")
            return 4
        }
    }

    private static func find(_ name: String, in items: [ManagedMenuBarItem]) -> ManagedMenuBarItem? {
        let matches = items.filter {
            [$0.bundleIdentifier, $0.title, $0.displayName].contains { $0.caseInsensitiveCompare(name) == .orderedSame }
        }
        return matches.count == 1 ? matches[0] : nil
    }
}

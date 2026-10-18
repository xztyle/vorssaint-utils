// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import AppKit

/// macOS 27 keeps icon order inside MenuBarAgent and ignores edits to its
/// preference file. A visible Command-drag is the only accepted reorder; the
/// agent then persists the order itself. Each attempt starts from fresh frames.
@MainActor
final class MenuBarNativeDragMover {
    private static let attempts = 3
    private let transport: MenuBarVisibleDragTransport
    private let snapshot: () async -> MenuBarItemSnapshot

    init(transport: MenuBarVisibleDragTransport = MenuBarVisibleDragTransport(),
         snapshot: @escaping () async -> MenuBarItemSnapshot = { await MenuBarNativeAXProvider.snapshot(includingOwn: true) }) {
        self.transport = transport
        self.snapshot = snapshot
    }

    func move(_ identity: MenuBarItemIdentity, before target: MenuBarItemIdentity) async throws {
        guard identity != target else { return }
        for attempt in 0..<Self.attempts {
            let (source, destination, all) = try await frames(identity, target)
            if MenuBarMoveGeometry.isBefore(source, destination, among: all) { return }
            let start = MenuBarMoveGeometry.pressPoint(in: source)
            let end = CGPoint(x: MenuBarMoveGeometry.dropX(source: source, target: destination, attempt: attempt), y: start.y)
            try await transport.drag(from: start, region: MenuBarMoveGeometry.dragRow(source, destination),
                                     validateSource: {}, destination: { end })
            try await Task.sleep(for: .milliseconds(250))
        }
        let (source, destination, all) = try await frames(identity, target)
        guard MenuBarMoveGeometry.isBefore(source, destination, among: all) else { throw MenuBarItemMoveError.verificationFailed }
    }

    private func frames(_ identity: MenuBarItemIdentity, _ target: MenuBarItemIdentity) async throws -> (CGRect, CGRect, [CGRect]) {
        let current = await snapshot()
        guard current.enumerationSucceeded,
              let source = current.items.first(where: { $0.id == identity }),
              let destination = current.items.first(where: { $0.id == target }) else {
            throw MenuBarItemMoveError.itemUnavailable
        }
        guard !source.isProtected else { throw MenuBarItemMoveError.itemNotMovable }
        return (source.frame, destination.frame, current.items.map(\.frame))
    }
}

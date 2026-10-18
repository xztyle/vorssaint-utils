// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors
// Layout invalidation follows Thaw's public ControlItem refresh, revision
// 528b9503b051cc1ccccae766014e64404670088b.

import Foundation

@MainActor
final class MenuBarNativeLayoutRefresh {
    private let length: () -> CGFloat
    private let width: () -> CGFloat
    private let setLength: (CGFloat) -> Void
    private let pause: (Duration) async throws -> Void
    private var task: Task<Void, Never>?
    private var temporary: (before: CGFloat, after: CGFloat)?

    init(length: @escaping () -> CGFloat, width: @escaping () -> CGFloat,
         setLength: @escaping (CGFloat) -> Void,
         pause: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.length = length; self.width = width; self.setLength = setLength; self.pause = pause
    }

    func request() {
        cancel()
        task = Task { [weak self, pause] in
            do { try await pause(.milliseconds(50)) } catch { return }
            guard let self, !Task.isCancelled, begin() else { return }
            do { try await pause(.milliseconds(16)) } catch {
                if !Task.isCancelled { restore() }
                return
            }
            guard !Task.isCancelled else { return }
            restore(); task = nil
        }
    }

    func cancel() {
        task?.cancel(); task = nil
        restore()
    }

    private func begin() -> Bool {
        let original = length(), rendered = width()
        guard rendered.isFinite, rendered > 0, original.isFinite else { return false }
        let updated = original < 0 || abs(original - rendered) > 0.25 ? rendered : rendered + 0.5
        temporary = (original, updated)
        setLength(updated)
        return true
    }

    private func restore() {
        guard let temporary else { return }
        self.temporary = nil
        if length() == temporary.after { setLength(temporary.before) }
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import Foundation

enum MenuBarNativeRefreshTests {
    @MainActor
    final class Surface {
        var length: CGFloat = -2
        var width: CGFloat = 24
        var writes: [CGFloat] = []
        var delays: [Duration] = []
        var waiting: [CheckedContinuation<Void, Never>] = []

        func pause(_ duration: Duration) async {
            delays.append(duration)
            await withCheckedContinuation { waiting.append($0) }
        }

        func refresh() -> MenuBarNativeLayoutRefresh {
            MenuBarNativeLayoutRefresh(length: { self.length }, width: { self.width },
                setLength: { self.length = $0; self.writes.append($0) }, pause: pause)
        }

        func advance() async {
            let deadline = Date().addingTimeInterval(1)
            while waiting.isEmpty, Date() < deadline { await Task.yield() }
            guard !waiting.isEmpty else { return }
            waiting.removeFirst().resume()
            for _ in 0..<10 { await Task.yield() }
        }
    }

    static func run(_ suite: TestSuite) {
        var finished = false
        Task { @MainActor in
            await normal(suite); await cancellation(suite); await overlap(suite)
            await concurrentChange(suite); await missingWidth(suite)
            finished = true
        }
        let deadline = Date().addingTimeInterval(6)
        while !finished, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.002)) }
        suite.expect(finished, "native layout refresh checks finish without OS input")
    }

    @MainActor
    private static func normal(_ suite: TestSuite) async {
        for original: CGFloat in [-2, -1, 24] {
            let surface = Surface(); surface.length = original
            let refresh = surface.refresh(); refresh.request()
            suite.expect(surface.writes.isEmpty, "layout waits for the preference change before invalidating width")
            await surface.advance()
            suite.expect(surface.writes == [original < 0 ? 24 : 24.5], "sentinel lengths become a valid rendered width")
            await surface.advance()
            suite.expect(surface.length == original, "completed refresh restores the original icon length")
            suite.expect(surface.delays == [.milliseconds(50), .milliseconds(16)], "macOS gets a separate layout pass before restoration")
        }
    }

    @MainActor
    private static func cancellation(_ suite: TestSuite) async {
        let surface = Surface(), refresh = surface.refresh()
        refresh.request(); await surface.advance(); refresh.cancel()
        suite.expect(surface.writes == [24, -2], "cancellation restores an active temporary width immediately")
        await surface.advance()
        suite.expect(surface.writes == [24, -2], "cancelled continuation cannot write again")
        refresh.request(); refresh.cancel(); await surface.advance()
        suite.expect(surface.writes == [24, -2], "cancellation during the initial delay never changes width")
    }

    @MainActor
    private static func overlap(_ suite: TestSuite) async {
        let surface = Surface(), refresh = surface.refresh()
        refresh.request(); await surface.advance(); refresh.request()
        suite.expect(surface.length == -2, "a replacement refresh first restores the previous width")
        await surface.advance(); await surface.advance(); await surface.advance()
        suite.expect(surface.writes == [24, -2, 24, -2], "overlapping refreshes cannot leave or overwrite a temporary width")
    }

    @MainActor
    private static func concurrentChange(_ suite: TestSuite) async {
        let surface = Surface(), refresh = surface.refresh()
        refresh.request(); await surface.advance(); surface.length = 99; await surface.advance()
        suite.expect(surface.length == 99 && surface.writes == [24], "restoration preserves a newer external length change")
    }

    @MainActor
    private static func missingWidth(_ suite: TestSuite) async {
        for width: CGFloat in [0, -.infinity, .nan] {
            let surface = Surface(); surface.width = width
            let refresh = surface.refresh(); refresh.request(); await surface.advance()
            suite.expect(surface.writes.isEmpty, "an unavailable rendered width never reaches AppKit")
        }
    }
}

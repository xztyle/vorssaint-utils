// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import AppKit

/// Production start/install/close bodies run against inert ports and run loops.
/// These tests never install a real event tap or observe keyboard/mouse input.
enum MenuBarTapLifecycleTests {
    final class Port {
        let id: Int
        var enabled = false
        var invalidations = 0
        init(_ id: Int) { self.id = id }
    }
    final class Source {
        var attached = false
    }
    enum EventAPI {
        static var records: [Port] = []
        static var attempts = 0
        static var failAt = 0
        static func make() -> Port? {
            attempts += 1
            guard attempts != failAt else { return nil }
            let port = Port(attempts); records.append(port); return port
        }
        static func tapCreateForPid(pid: pid_t, place: CGEventTapPlacement, options: CGEventTapOptions,
            eventsOfInterest: CGEventMask, callback: CGEventTapCallBack, userInfo: UnsafeMutableRawPointer?) -> Port? { make() }
        static func tapCreate(tap: CGEventTapLocation, place: CGEventTapPlacement, options: CGEventTapOptions,
            eventsOfInterest: CGEventMask, callback: CGEventTapCallBack, userInfo: UnsafeMutableRawPointer?) -> Port? { make() }
        static func tapEnable(tap: Port, enable: Bool) { tap.enabled = enable }
    }
    class Fixture {
        typealias CFMachPort = Port
        typealias CFRunLoopSource = Source
        typealias CGEvent = EventAPI
        enum MenuBarItemMoveError: Error { case eventCreationFailed, busy }
        let pid: pid_t = 42
        var taps: [(Port, Source)] = []
        var sources: [Source] = []
        var failSourceAt = 0
        var waiting = false
        var cancellations = 0
        static let targetCallback: CGEventTapCallBack = { _, _, event, _ in Unmanaged.passUnretained(event) }
        static let sessionCallback = targetCallback
        func CFMachPortCreateRunLoopSource(_ allocator: CFAllocator?, _ port: Port, _ order: CFIndex) -> Source? {
            guard port.id != failSourceAt else { return nil }
            let source = Source(); sources.append(source); return source
        }
        func CFRunLoopAddSource(_ loop: CFRunLoop?, _ source: Source, _ mode: CFRunLoopMode) { source.attached = true }
        func CFRunLoopRemoveSource(_ loop: CFRunLoop?, _ source: Source, _ mode: CFRunLoopMode) { source.attached = false }
        func CFMachPortInvalidate(_ port: Port) { port.invalidations += 1 }
        func finish(_ result: Result<Void, Error>) {
            if waiting, case .failure(let error) = result, error is CancellationError { cancellations += 1 }
            waiting = false
        }
    }

    static func run(_ suite: TestSuite) {
        for index in 1...2 {
            let creation = fixture(); EventAPI.failAt = index
            suite.expect((try? creation.start()) == nil, "tap creation failure propagates")
            closed(creation, suite, "tap \(index) creation failure")
            let source = fixture(); source.failSourceAt = index
            suite.expect((try? source.start()) == nil, "run-loop source failure propagates without a trap")
            closed(source, suite, "tap \(index) run-loop source failure")
        }
        let normal = fixture()
        do { try normal.start() } catch { suite.expect(false, "normal tap setup: \(error)"); return }
        suite.expect(normal.taps.count == 2 && normal.sources.allSatisfy(\.attached), "normal setup owns and attaches both taps")
        suite.expect((try? normal.start()) == nil && normal.taps.count == 2, "repeated setup preserves existing ownership instead of adding taps")
        normal.waiting = true
        normal.close(); normal.close()
        closed(normal, suite, "normal/cancelled delivery teardown")
        suite.expect(normal.cancellations == 1, "teardown cancels a pending waiter once, even when closed twice")
    }

    private static func fixture() -> Host {
        EventAPI.records = []; EventAPI.attempts = 0; EventAPI.failAt = 0
        return Host()
    }

    private static func closed(_ host: Host, _ suite: TestSuite, _ context: String) {
        suite.expect(host.taps.isEmpty && host.sources.allSatisfy { !$0.attached }, "\(context) detaches every installed source")
        suite.expect(EventAPI.records.allSatisfy { !$0.enabled && $0.invalidations == 1 },
                     "\(context) invalidates each successfully created port exactly once, including unregistered ports")
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation

/// The fallback can run off the main thread if an application stalls mid-drag.
final class MenuBarPressReleaseGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var armed = true
    private let postRelease: () -> Void
    private var watchdog: DispatchWorkItem?

    init(postRelease: @escaping () -> Void) { self.postRelease = postRelease }

    func schedule() {
        let work = DispatchWorkItem { [weak self] in self?.releaseIfArmed() }
        watchdog = work
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 3, execute: work)
    }

    func confirmRelease() {
        lock.lock(); armed = false; lock.unlock()
        watchdog?.cancel()
    }

    func releaseIfArmed() {
        lock.lock()
        let shouldRelease = armed
        armed = false
        lock.unlock()
        if shouldRelease { postRelease() }
    }
}

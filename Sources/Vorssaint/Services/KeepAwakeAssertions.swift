// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Aster contributors

import Foundation
import IOKit.pwr_mgt

/// Reacquires assertions if macOS's power service restarts. Session intent
/// remains in KeepAwakeManager; an expired handle is never treated as active.
final class KeepAwakeAssertions {
    enum Kind: String { case system = "PreventUserIdleSystemSleep", display = "PreventUserIdleDisplaySleep" }
    private let create: (Kind) -> IOPMAssertionID?
    private let valid: (IOPMAssertionID, Kind) -> Bool
    private let release: (IOPMAssertionID) -> Void
    private var system: IOPMAssertionID?
    private var display: IOPMAssertionID?

    init(create: @escaping (Kind) -> IOPMAssertionID? = KeepAwakeAssertions.create,
         valid: @escaping (IOPMAssertionID, Kind) -> Bool = KeepAwakeAssertions.valid,
         release: @escaping (IOPMAssertionID) -> Void = { _ = IOPMAssertionRelease($0) }) {
        self.create = create; self.valid = valid; self.release = release
    }

    func apply(allowDisplaySleep: Bool) {
        refresh(&system, kind: .system)
        if allowDisplaySleep { discard(&display, kind: .display) }
        else { refresh(&display, kind: .display) }
    }

    func clear() { discard(&system, kind: .system); discard(&display, kind: .display) }

    private func refresh(_ id: inout IOPMAssertionID?, kind: Kind) {
        if let existing = id, !valid(existing, kind) { id = nil }
        if id == nil { id = create(kind) }
    }

    private func discard(_ id: inout IOPMAssertionID?, kind: Kind) {
        if let existing = id, valid(existing, kind) { release(existing) }
        id = nil
    }

    private static func name(_ kind: Kind) -> String {
        kind == .system ? "Aster: keep the Mac awake" : "Aster: keep the display on"
    }

    private static func create(_ kind: Kind) -> IOPMAssertionID? {
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(kind.rawValue as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn), name(kind) as CFString, &id)
        return result == kIOReturnSuccess ? id : nil
    }

    private static func valid(_ id: IOPMAssertionID, _ kind: Kind) -> Bool {
        guard let values = IOPMAssertionCopyProperties(id)?.takeRetainedValue() as? [String: Any] else { return false }
        return values[kIOPMAssertionNameKey as String] as? String == name(kind)
            && values[kIOPMAssertionTypeKey as String] as? String == kind.rawValue
            && values[kIOPMAssertionLevelKey as String] as? Int == Int(kIOPMAssertionLevelOn)
    }
}

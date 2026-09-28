// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import Foundation

extension BatteryController {
    func runSchedules() {
        let now = Date()
        let occurrences = BatteryScheduler.due(state.policy.schedules, since: state.scheduleCursor,
                                               now: now, fired: Set(state.fired))
        // Commit occurrence claims with resulting state in one journal write.
        // Same-time tasks use stable UUID order; the first exclusive action wins.
        for occurrence in occurrences {
            state.fired.append(occurrence.key)
            applySchedule(occurrence.schedule, now: now)
        }
        state.fired = Array(state.fired.suffix(256))
        if !occurrences.isEmpty || now.timeIntervalSince(lastSaved) >= 60 {
            state.scheduleCursor = now
            _ = save()
        }
    }

    private func applySchedule(_ schedule: BatterySchedule, now: Date) {
        if schedule.action == .system {
            state.cancelOperation()
            state.scheduledPause = true
            state.record(.system, at: now, detail: schedule.id.uuidString)
            return
        }
        guard state.operation == nil else {
            state.record(.busy, at: now, detail: schedule.id.uuidString)
            return
        }
        state.scheduledPause = false
        switch schedule.action {
        case .limit:
            state.policy.upper = schedule.target
            state.policy.lower = min(state.policy.lower, schedule.target - 1)
            state.chargingLatch = false
        case .topUp: _ = BatteryPolicy.begin(.topUp, state: &state, now: now)
        case .discharge, .calibrate:
            guard state.dischargeQualified else {
                state.record(.unavailable, at: now, detail: schedule.id.uuidString)
                return
            }
            let kind: BatteryOperationKind = schedule.action == .discharge ? .discharge : .calibration
            _ = BatteryPolicy.begin(kind, target: min(99, schedule.target), state: &state, now: now)
        case .system: break
        }
    }
}

/// Process presence is a conservative refusal, not proof of exclusive control.
/// Unexpected key drift supplies the independent control-integrity check.
enum BatteryCompetitors {
    static func running() -> [String] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "comm="]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return ["process-inspection-unavailable"] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return ["process-inspection-unavailable"] }
        let paths = String(decoding: data, as: UTF8.self).split(separator: "\n")
        return Array(Set(paths.compactMap { path -> String? in
            let value = path.lowercased()
            if value.contains("aldente") { return "AlDente" }
            if value.contains("stasis") { return "Stasis" }
            let name = URL(fileURLWithPath: String(path)).lastPathComponent
            return ["batt", "battery", "smc"].contains(name) ? name : nil
        })).sorted()
    }
}

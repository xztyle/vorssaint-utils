// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import Foundation

struct BatteryCarePolicy: Codable, Equatable {
    var version = 1
    var enabled = false
    var lower = 75
    var upper = 80
    var heatCutoff = 38.0
    var heatResume = 35.0
    var automaticDischarge = true
    var schedules: [BatterySchedule] = []

    var isValid: Bool {
        version == 1 && (20...99).contains(lower) && (21...100).contains(upper)
            && lower < upper && heatCutoff.isFinite && heatResume.isFinite
            && (30...45).contains(heatCutoff) && (20...44).contains(heatResume)
            && heatResume <= heatCutoff - 2 && schedules.count <= 32
            && Set(schedules.map(\.id)).count == schedules.count
            && schedules.allSatisfy(\.isValid)
    }
}

enum BatteryCommand: String, Codable { case system, charge, hold, discharge }
enum BatteryOperationKind: String, Codable { case discharge, topUp, calibration }
enum BatteryCalibrationPhase: String, Codable { case charge, discharge, recharge, hold }
enum BatteryReason: String, Codable {
    case system, charging, holding, discharging, unplugged, heat, cooling, staleSensor
    case unavailable, conflict, recovery, paused, topUp, calibration, sleeping, qualifying
    case invalidRequest, busy, timeout, writeFailed, verificationFailed, journalFailed, helperUnavailable
}

struct BatterySample: Codable, Equatable {
    var at: Date
    var percent: Int?
    var temperature: Double?
    var connected: Bool?
    var charging: Bool?
    var watts: Double?
    var adapterWatts: Double?

    func isFresh(at now: Date) -> Bool {
        guard let percent, let temperature, let watts, connected != nil, charging != nil else { return false }
        return (-2...20).contains(now.timeIntervalSince(at)) && (0...100).contains(percent)
            && temperature.isFinite && (0...65).contains(temperature)
            && watts.isFinite && abs(watts) < 400
    }
}

struct BatteryOperation: Codable, Equatable {
    var id = UUID()
    var kind: BatteryOperationKind
    var savedPolicy: BatteryCarePolicy
    var startedAt: Date
    var phase: BatteryCalibrationPhase = .charge
    var phaseStartedAt: Date
    var target: Int = 10
    var paused = false
    var holdSeconds: TimeInterval = 0
}

struct BatteryCareState: Codable, Equatable {
    var version = 1
    var policy = BatteryCarePolicy()
    var operation: BatteryOperation?
    var scheduledPause = false
    var chargingLatch = false
    var heatLatched = false
    var coolSince: Date?
    var dischargeStarted: Date?
    var lastTick: Date?
    var scheduleCursor: Date = Date()
    var fired: [String] = []
    var ownsHardware = false
    var recoveryPending = false
    var qualifiedFingerprint: String?
    var chargeQualified = false
    var dischargeQualified = false
    var events: [BatteryCareEvent] = []

    var isValid: Bool {
        version == 1 && policy.isValid && fired.count <= 256 && events.count <= 100
            && (operation == nil || (operation!.savedPolicy.isValid
                && (10...99).contains(operation!.target)))
    }

    mutating func record(_ reason: BatteryReason, at date: Date, detail: String? = nil) {
        if events.last?.reason == reason && detail == events.last?.detail { return }
        events.append(BatteryCareEvent(at: date, reason: reason, detail: detail))
        events = Array(events.suffix(100))
    }

    mutating func cancelOperation() {
        if let operation { policy = operation.savedPolicy }
        operation = nil
        dischargeStarted = nil
        chargingLatch = false
    }
}

struct BatteryCareEvent: Codable, Equatable, Identifiable {
    var id = UUID()
    let at: Date
    let reason: BatteryReason
    var detail: String?
}

struct BatteryDecision: Equatable {
    var command: BatteryCommand
    var reason: BatteryReason
}

struct BatteryCareSnapshot: Codable {
    var state = BatteryCareState()
    var sample: BatterySample?
    var reason: BatteryReason = .system
    var command: BatteryCommand = .system
    var chargeCandidate = false
    var dischargeCandidate = false
    var fingerprint = ""
    var diagnostic: String?
    var competitors: [String] = []
    var qualificationStep: Int?
    var helperBuild = ""
}

struct BatteryCareResponse: Codable {
    var succeeded: Bool
    var snapshot: BatteryCareSnapshot
}

enum BatteryRequestKind: String, Codable {
    case configure, discharge, topUp, calibrate, cancel, resume, returnToSystem, qualify
}

struct BatteryCareRequest: Codable {
    var version = 1
    var kind: BatteryRequestKind
    var policy: BatteryCarePolicy?
    var target: Int?

    var isValid: Bool {
        version == 1 && (policy == nil || policy!.isValid)
            && (kind != .configure || policy != nil)
            && (kind != .discharge || (10...99).contains(target ?? -1))
    }
}

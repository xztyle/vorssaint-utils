// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import Foundation

enum BatteryRepeat: String, Codable, CaseIterable { case once, daily, weekdays, weekly, biweekly, monthly }
enum BatteryScheduleAction: String, Codable, CaseIterable { case limit, topUp, discharge, calibrate, system }

struct BatterySchedule: Codable, Equatable, Identifiable {
    var id = UUID()
    var enabled = true
    var start: Date = Date().addingTimeInterval(3600)
    var timeZone: String = TimeZone.current.identifier
    var repetition: BatteryRepeat = .daily
    var action: BatteryScheduleAction = .limit
    var target = 80
    var runMissed = false

    var isValid: Bool {
        TimeZone(identifier: timeZone) != nil && start.timeIntervalSince1970.isFinite
            && (10...100).contains(target) && (action != .limit || target >= 21)
    }
}

struct BatteryOccurrence: Equatable {
    let schedule: BatterySchedule
    let date: Date
    let key: String
}

enum BatteryScheduler {
    /// A missed task has a six-hour freshness window. Civil-day identities fire
    /// once through DST folds; nonexistent local times use the next valid time.
    static func due(_ schedules: [BatterySchedule], since: Date, now: Date,
                    fired: Set<String>) -> [BatteryOccurrence] {
        guard now >= since else { return [] }
        return schedules.filter { $0.enabled && $0.isValid }.compactMap { schedule in
            guard let date = latestOccurrence(schedule, now: now), date > since,
                  now.timeIntervalSince(date) <= (schedule.runMissed ? 21600 : 90) else { return nil }
            let key = occurrenceKey(schedule, date: date)
            guard !fired.contains(key) else { return nil }
            return BatteryOccurrence(schedule: schedule, date: date, key: key)
        }.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.schedule.id.uuidString < $1.schedule.id.uuidString
        }
    }

    static func latestOccurrence(_ schedule: BatterySchedule, now: Date) -> Date? {
        guard let zone = TimeZone(identifier: schedule.timeZone), now >= schedule.start else { return nil }
        if schedule.repetition == .once { return schedule.start }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let time = calendar.dateComponents([.hour, .minute], from: schedule.start)
        for back in 0...35 {
            guard let day = calendar.date(byAdding: .day, value: -back, to: now),
                  matches(schedule, day: day, calendar: calendar),
                  let candidate = calendar.nextDate(after: calendar.startOfDay(for: day).addingTimeInterval(-1),
                    matching: time, matchingPolicy: .nextTime, repeatedTimePolicy: .first),
                  calendar.isDate(candidate, inSameDayAs: day), candidate <= now,
                  candidate >= schedule.start else { continue }
            return candidate
        }
        return nil
    }

    private static func matches(_ schedule: BatterySchedule, day: Date, calendar: Calendar) -> Bool {
        let start = schedule.start
        let weekday = calendar.component(.weekday, from: day)
        switch schedule.repetition {
        case .once: return calendar.isDate(start, inSameDayAs: day)
        case .daily: return true
        case .weekdays: return (2...6).contains(weekday)
        case .weekly: return weekday == calendar.component(.weekday, from: start)
        case .biweekly:
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start),
                                                to: calendar.startOfDay(for: day)).day ?? -1
            return days >= 0 && days % 14 == 0
        case .monthly: return calendar.component(.day, from: day) == calendar.component(.day, from: start)
        }
    }

    private static func occurrenceKey(_ schedule: BatterySchedule, date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: schedule.timeZone)!
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(schedule.id.uuidString):\(parts.year!)-\(parts.month!)-\(parts.day!)"
    }
}

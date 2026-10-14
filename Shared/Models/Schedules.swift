//
//  Schedules.swift
//  Gatita
//

import Foundation

/// When a scheduled prompt runs: every day, every weekday, once a week, or every hour, at a time.
nonisolated struct Schedule: Codable, Equatable, Sendable {
    enum Repeat: String, Codable, CaseIterable, Identifiable, Sendable {
        case daily, weekdays, weekly, hourly

        var id: String { rawValue }

        var title: String {
            switch self {
            case .daily: "Every day"
            case .weekdays: "Weekdays"
            case .weekly: "Every week"
            case .hourly: "Every hour"
            }
        }
    }

    var repeats: Repeat
    var hour: Int
    var minute: Int
    /// 1 (Sunday) to 7 (Saturday), for a weekly prompt.
    var weekday: Int?
}

/// A prompt Gatita runs on its own, like ChatGPT's scheduled tasks or a nightly job. Mac only, while Gatita is open.
nonisolated struct ScheduledPrompt: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var prompt: String
    var mode: GatitaMode
    var schedule: Schedule
    var enabled: Bool
    let createdAt: Date
    var lastRun: Date?
}

nonisolated enum ScheduleMath {
    /// A run missed while the Mac slept still runs when it wakes, if it was due at most this long ago.
    static let catchUpWindow: TimeInterval = 12 * 3_600

    enum Decision: Equatable {
        /// Run it now.
        case run
        /// It was due too long ago: don't run it late, wait for the next time.
        case skip
        /// Not due yet.
        case wait
    }

    /// The first time after `date` the schedule runs. Clock changes give one run a day: a time that does not
    /// exist runs at the next one that does, and a time that happens twice runs the first time.
    static func nextRun(after date: Date, _ schedule: Schedule, _ calendar: Calendar = .current) -> Date {
        var parts = DateComponents(minute: schedule.minute, second: 0)
        if schedule.repeats != .hourly { parts.hour = schedule.hour }
        if schedule.repeats == .weekly { parts.weekday = schedule.weekday ?? 2 }
        func next(after date: Date) -> Date {
            calendar.nextDate(after: date, matching: parts, matchingPolicy: .nextTime, repeatedTimePolicy: .first)
                ?? date.addingTimeInterval(schedule.repeats == .hourly ? 3_600 : 86_400)
        }
        var candidate = next(after: date)
        while schedule.repeats == .weekdays, [1, 7].contains(calendar.component(.weekday, from: candidate)) {
            candidate = next(after: candidate)
        }
        return candidate
    }

    /// Whether a prompt runs now. Only the latest missed time counts, so a Mac that slept for days runs it once.
    static func decision(for prompt: ScheduledPrompt, now: Date, _ calendar: Calendar = .current) -> Decision {
        guard prompt.enabled else { return .wait }
        var due: Date?
        var next = nextRun(after: prompt.lastRun ?? prompt.createdAt, prompt.schedule, calendar)
        var steps = 0
        while next <= now, steps < 10_000 {
            due = next
            next = nextRun(after: next, prompt.schedule, calendar)
            steps += 1
        }
        guard let due else { return .wait }
        return now.timeIntervalSince(due) <= catchUpWindow ? .run : .skip
    }

    /// When a schedule runs, in words: "Every day at 8:30 AM", "Mondays at 9:00 AM", "Every hour at :05".
    static func summary(_ schedule: Schedule, _ calendar: Calendar = .current) -> String {
        if schedule.repeats == .hourly { return String(format: "Every hour at :%02d", schedule.minute) }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale ?? .current
        formatter.timeStyle = .short
        let time = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: schedule.hour, minute: schedule.minute))
            .map(formatter.string) ?? "\(schedule.hour):\(schedule.minute)"
        switch schedule.repeats {
        case .weekly:
            let day = formatter.weekdaySymbols[((schedule.weekday ?? 2) - 1 + 7) % 7]
            return "\(day)s at \(time)"
        default:
            return "\(schedule.repeats.title) at \(time)"
        }
    }

    /// The saved chat's title for one run, such as "News · Oct 13".
    static func chatTitle(name: String, at date: Date, _ calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale ?? .current
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return "\(name) · \(formatter.string(from: date))"
    }
}

/// Scheduled prompts in Application Support/Gatita/schedules.json.
nonisolated enum ScheduleStore {
    static var defaultFile: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Gatita/schedules.json")
    }

    static func load(from file: URL) -> [ScheduledPrompt] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        return (try? JSONDecoder().decode([ScheduledPrompt].self, from: data)) ?? []
    }

    static func save(_ prompts: [ScheduledPrompt], to file: URL) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(prompts) {
            try? data.write(to: file, options: .atomic)
        }
    }
}

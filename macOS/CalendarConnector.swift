//
//  CalendarConnector.swift
//  Gatita
//

#if os(macOS)
import EventKit
import Foundation

/// Reads events from the Mac's calendars through EventKit. Read-only: it never creates or changes an event.
nonisolated enum CalendarConnector {
    static let defaultDays = 7
    static let maxDays = 31

    /// One event, reduced to what the model needs.
    struct EventSummary: Equatable, Sendable {
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        let calendarName: String
        let location: String?
    }

    /// The window a calendar_events call asks for: whole days from the start of `start` (YYYY-MM-DD, default today).
    static func window(start: String?, days: String?, now: Date = Date(), calendar: Calendar = .current) throws -> DateInterval {
        let first: Date
        if let start, !start.isEmpty {
            guard let day = makeFormatter("yyyy-MM-dd", calendar: calendar).date(from: start) else {
                throw ToolError("start must be a day as YYYY-MM-DD, such as 2026-10-08")
            }
            first = day
        } else {
            first = calendar.startOfDay(for: now)
        }

        let count: Int
        if let days, !days.isEmpty {
            guard let number = Int(days) else { throw ToolError("days must be a whole number") }
            count = min(max(number, 1), maxDays)
        } else {
            count = defaultDays
        }
        guard let last = calendar.date(byAdding: .day, value: count, to: first) else {
            throw ToolError("that date range is not valid")
        }
        return DateInterval(start: first, end: last)
    }

    /// The events as lines, earliest first, each with its time, title, calendar, and location.
    static func format(_ events: [EventSummary], calendar: Calendar = .current) -> String {
        guard !events.isEmpty else { return "(no events)" }
        let dayFormatter = makeFormatter("yyyy-MM-dd", calendar: calendar)
        let timeFormatter = makeFormatter("yyyy-MM-dd HH:mm", calendar: calendar)
        return events.sorted { $0.start < $1.start }.map { event in
            let when = event.isAllDay
                ? "\(dayFormatter.string(from: event.start)), all day"
                : "\(timeFormatter.string(from: event.start)) to \(timeFormatter.string(from: event.end))"
            var line = "\(when) · \(event.title) · \(event.calendarName)"
            if let location = event.location, !location.isEmpty {
                line += " · \(location)"
            }
            return line
        }.joined(separator: "\n")
    }

    /// Asks for calendar access if it has not been given yet, then returns the events that overlap the window.
    static func events(in window: DateInterval) async throws -> [EventSummary] {
        let store = EKEventStore()
        let granted = try await store.requestFullAccessToEvents()
        guard granted else {
            throw ToolError("Gatita cannot read your calendars. Allow Gatita under System Settings, Privacy & Security, Calendars.")
        }
        let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: nil)
        return store.events(matching: predicate).map { event in
            EventSummary(title: event.title ?? "(untitled)", start: event.startDate, end: event.endDate,
                         isAllDay: event.isAllDay, calendarName: event.calendar?.title ?? "Calendar",
                         location: event.location)
        }
    }

    /// Runs calendar_events with its arguments: "start" and "days", both optional.
    static func run(_ arguments: [String: String]) async throws -> String {
        let range = try window(start: arguments["start"], days: arguments["days"])
        return format(try await events(in: range))
    }

    private static func makeFormatter(_ pattern: String, calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        return formatter
    }
}
#endif

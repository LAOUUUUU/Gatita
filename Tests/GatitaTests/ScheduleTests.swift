//
//  ScheduleTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// Scheduled prompts: when each runs next, and what happens to runs missed while the Mac slept.
final class ScheduleTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()

    private func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }

    private func schedule(_ repeats: Schedule.Repeat, _ hour: Int, _ minute: Int, weekday: Int? = nil) -> Schedule {
        Schedule(repeats: repeats, hour: hour, minute: minute, weekday: weekday)
    }

    func testADailyPromptRunsAtItsTimeToday_orTomorrow() {
        let daily = schedule(.daily, 8, 30)
        XCTAssertEqual(ScheduleMath.nextRun(after: date("2026-10-13 07:00"), daily, calendar), date("2026-10-13 08:30"))
        XCTAssertEqual(ScheduleMath.nextRun(after: date("2026-10-13 08:30"), daily, calendar), date("2026-10-14 08:30"))
    }

    func testWeekdaysSkipTheWeekend() {
        // 2026-10-16 is a Friday.
        XCTAssertEqual(ScheduleMath.nextRun(after: date("2026-10-16 09:00"), schedule(.weekdays, 8, 30), calendar),
                       date("2026-10-19 08:30"))
    }

    func testWeeklyRunsOnItsDay() {
        // Weekday 1 is Sunday; 2026-10-18 is a Sunday.
        XCTAssertEqual(ScheduleMath.nextRun(after: date("2026-10-13 12:00"), schedule(.weekly, 20, 0, weekday: 1), calendar),
                       date("2026-10-18 20:00"))
    }

    func testHourlyRunsAtItsMinute() {
        let hourly = schedule(.hourly, 0, 15)
        XCTAssertEqual(ScheduleMath.nextRun(after: date("2026-10-13 10:05"), hourly, calendar), date("2026-10-13 10:15"))
        XCTAssertEqual(ScheduleMath.nextRun(after: date("2026-10-13 10:20"), hourly, calendar), date("2026-10-13 11:15"))
    }

    func testClockChangesStillGiveOneRunADay() {
        // Clocks go forward at 2:00 on 2027-03-14, so 2:30 does not exist that day.
        let spring = ScheduleMath.nextRun(after: date("2027-03-13 22:00"), schedule(.daily, 2, 30), calendar)
        XCTAssertEqual(calendar.component(.day, from: spring), 14)
        XCTAssertEqual(calendar.component(.hour, from: spring), 3)
        // Clocks go back at 2:00 on 2026-11-01, so 1:30 happens twice; it runs once.
        let fall = ScheduleMath.nextRun(after: date("2026-10-31 22:00"), schedule(.daily, 1, 30), calendar)
        let after = ScheduleMath.nextRun(after: fall, schedule(.daily, 1, 30), calendar)
        XCTAssertEqual(calendar.component(.day, from: fall), 1)
        XCTAssertEqual(calendar.component(.day, from: after), 2)
    }

    // MARK: - Due runs

    private func prompt(lastRun: String, enabled: Bool = true) -> ScheduledPrompt {
        ScheduledPrompt(id: UUID(), name: "News", prompt: "Summarize the news", mode: .chat,
                        schedule: schedule(.daily, 8, 30), enabled: enabled, createdAt: date("2026-10-01 00:00"),
                        lastRun: date(lastRun))
    }

    func testARunThatIsDueRuns() {
        XCTAssertEqual(ScheduleMath.decision(for: prompt(lastRun: "2026-10-12 08:30"), now: date("2026-10-13 08:31"), calendar), .run)
        XCTAssertEqual(ScheduleMath.decision(for: prompt(lastRun: "2026-10-12 08:30"), now: date("2026-10-13 08:00"), calendar), .wait)
        XCTAssertEqual(ScheduleMath.decision(for: prompt(lastRun: "2026-10-12 08:30", enabled: false), now: date("2026-10-13 08:31"), calendar), .wait)
    }

    func testARunMissedWhileAsleepRunsOnceWithinTwelveHours() {
        // Asleep for three days: only the latest missed run counts, and it was 4 hours ago.
        XCTAssertEqual(ScheduleMath.decision(for: prompt(lastRun: "2026-10-10 08:30"), now: date("2026-10-13 12:30"), calendar), .run)
        // Waking 13 hours after the run was due: it is skipped, not run late.
        XCTAssertEqual(ScheduleMath.decision(for: prompt(lastRun: "2026-10-12 08:30"), now: date("2026-10-13 21:31"), calendar), .skip)
    }

    func testScheduledPromptsAreSavedAndLoaded() {
        let file = temporaryFolder(self).appendingPathComponent("schedules.json")
        XCTAssertEqual(ScheduleStore.load(from: file), [])
        let prompts = [prompt(lastRun: "2026-10-12 08:30")]
        ScheduleStore.save(prompts, to: file)
        XCTAssertEqual(ScheduleStore.load(from: file), prompts)
    }

    func testEachScheduleSaysWhenItRuns() {
        // The system puts a narrow no-break space before AM and PM.
        func summary(_ schedule: Schedule) -> String {
            ScheduleMath.summary(schedule, calendar).replacingOccurrences(of: "\u{202F}", with: " ")
        }
        XCTAssertEqual(summary(schedule(.daily, 8, 30)), "Every day at 8:30 AM")
        XCTAssertEqual(summary(schedule(.weekdays, 18, 0)), "Weekdays at 6:00 PM")
        XCTAssertEqual(summary(schedule(.weekly, 9, 0, weekday: 2)), "Mondays at 9:00 AM")
        XCTAssertEqual(summary(schedule(.hourly, 0, 5)), "Every hour at :05")
    }

    func testAFinishedRunIsTitledAndNotified() {
        XCTAssertEqual(ScheduleMath.chatTitle(name: "News", at: date("2026-10-13 08:30"), calendar), "News · Oct 13")
        let note = Notifier.scheduledFinished(name: "News", reply: "## Today\n\nMarkets rose.")
        XCTAssertEqual(note.title, "Scheduled: News")
        XCTAssertEqual(note.body, "Today")
    }
}

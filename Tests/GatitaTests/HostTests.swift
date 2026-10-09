//
//  HostTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// Which host can do what, the streamed replies a client shows, and the Calendar connector's window and listing.
final class HostTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = try makeProjectFixture(self)
    }

    // MARK: - Host kinds

    func testOnlyTheMacUsesAProjectFolderAndGitHub() {
        XCTAssertNotNil(HostPolicy.projectRoot(root.path, on: .mac))
        XCTAssertNil(HostPolicy.projectRoot(root.path, on: .questionsOnly))
        XCTAssertNil(HostPolicy.projectRoot("   ", on: .mac))
        XCTAssertEqual(HostPolicy.connectors(["github", "web"], on: .mac), ["github", "web"])
        XCTAssertEqual(HostPolicy.connectors(["github", "web"], on: .questionsOnly), ["web"])
    }

    func testAHostWithoutAFolderListsNoFileToolsAndRefusesThem() {
        let phone = ProjectTools(root: nil, allowWrites: true, allowCommands: true, connectors: ["web"])
        let instructions = phone.instructions
        for tool in ["list_files", "read_file", "search_text", "git_status", "git_diff", "write_file", "edit_file", "run_command"] {
            XCTAssertFalse(instructions.contains("\"tool\": \"\(tool)\""), tool)
        }
        XCTAssertTrue(instructions.contains("\"tool\": \"web_fetch\""))
        XCTAssertTrue(instructions.contains("\"tool\": \"ask_user\""))
        XCTAssertTrue(phone.run(name: "write_file", arguments: #"{"path": "New.swift", "content": "x"}"#).hasPrefix("error:"))
        XCTAssertTrue(phone.run(name: "read_file", arguments: #"{"path": "App/GatitaApp.swift"}"#).hasPrefix("error:"))
        XCTAssertTrue(phone.run(name: "run_command", arguments: #"{"command": "swift --version"}"#).hasPrefix("error:"))
    }

    // MARK: - Streamed replies

    func testPiecesBuildTheReplyAndTheFinalResponseReplacesThem() {
        var assembler = ReplyAssembler()
        assembler.receive(.chunk(text: "Hel"))
        assembler.receive(.chunk(text: "lo"))
        XCTAssertEqual(assembler.text, "Hello")
        XCTAssertFalse(assembler.isFinished)

        assembler.receive(.response(text: "Hello there"))
        XCTAssertEqual(assembler.text, "Hello there")
        XCTAssertTrue(assembler.isFinished)

        assembler.receive(.chunk(text: "!"))
        XCTAssertEqual(assembler.text, "Hello there")
    }

    func testAPieceSurvivesTheWire() throws {
        let data = try JSONEncoder().encode(RemoteMessage.chunk(text: "Hi"))
        guard case .chunk(let text)? = try? JSONDecoder().decode(RemoteMessage.self, from: data) else {
            return XCTFail("the piece did not decode as a chunk")
        }
        XCTAssertEqual(text, "Hi")
    }

    // MARK: - Calendar

    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    func testCalendarWindowDefaultsToTodayAndSevenDays() throws {
        let window = try CalendarConnector.window(start: nil, days: nil, now: isoDate("2026-10-08T12:00:00Z"), calendar: utc)
        XCTAssertEqual(window.start, isoDate("2026-10-08T00:00:00Z"))
        XCTAssertEqual(window.end, isoDate("2026-10-15T00:00:00Z"))
    }

    func testCalendarWindowTakesAStartDayAndANumberOfDays() throws {
        let window = try CalendarConnector.window(start: "2026-11-01", days: "3", now: isoDate("2026-10-08T12:00:00Z"), calendar: utc)
        XCTAssertEqual(window.start, isoDate("2026-11-01T00:00:00Z"))
        XCTAssertEqual(window.end, isoDate("2026-11-04T00:00:00Z"))
    }

    func testCalendarWindowCapsTheDaysAt31() throws {
        let window = try CalendarConnector.window(start: "2026-11-01", days: "400", now: isoDate("2026-10-08T12:00:00Z"), calendar: utc)
        XCTAssertEqual(window.end.timeIntervalSince(window.start), 31 * 86_400)
    }

    func testCalendarWindowRefusesABadStartOrDays() {
        let now = isoDate("2026-10-08T12:00:00Z")
        XCTAssertThrowsError(try CalendarConnector.window(start: "next tuesday", days: nil, now: now, calendar: utc))
        XCTAssertThrowsError(try CalendarConnector.window(start: nil, days: "soon", now: now, calendar: utc))
    }

    func testCalendarEventsAreListedInStartOrderWithDetails() {
        let standup = CalendarConnector.EventSummary(title: "Standup", start: isoDate("2026-10-09T09:00:00Z"),
                                                     end: isoDate("2026-10-09T09:15:00Z"), isAllDay: false,
                                                     calendarName: "Work", location: nil)
        let dentist = CalendarConnector.EventSummary(title: "Dentist", start: isoDate("2026-10-08T16:00:00Z"),
                                                     end: isoDate("2026-10-08T17:00:00Z"), isAllDay: false,
                                                     calendarName: "Home", location: "Main St")
        let birthday = CalendarConnector.EventSummary(title: "Sam's birthday", start: isoDate("2026-10-10T00:00:00Z"),
                                                      end: isoDate("2026-10-11T00:00:00Z"), isAllDay: true,
                                                      calendarName: "Home", location: nil)
        let listed = CalendarConnector.format([birthday, standup, dentist], calendar: utc)

        let dentistAt = listed.range(of: "Dentist")?.lowerBound
        let standupAt = listed.range(of: "Standup")?.lowerBound
        let birthdayAt = listed.range(of: "Sam's birthday")?.lowerBound
        XCTAssertNotNil(dentistAt)
        XCTAssertNotNil(standupAt)
        XCTAssertNotNil(birthdayAt)
        XCTAssertLessThan(dentistAt!, standupAt!)
        XCTAssertLessThan(standupAt!, birthdayAt!)
        XCTAssertTrue(listed.contains("all day"))
        XCTAssertTrue(listed.contains("Main St"))
        XCTAssertTrue(listed.contains("Home"))
    }

    func testNoEventsGivesAClearAnswer() {
        XCTAssertEqual(CalendarConnector.format([], calendar: utc), "(no events)")
    }
}

//
//  ReplyTimeTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// The time under a reply: how long ago it came, and after a day the date written out with the time.
final class ReplyTimeTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    /// Friday, October 9, 2026 at 3:42 PM UTC.
    private let replied = Date(timeIntervalSince1970: 1_791_560_520)

    func testARecentReplySaysJustNow() {
        XCTAssertEqual(ReplyTime.label(since: replied, now: replied.addingTimeInterval(20), timeZone: utc), "just now")
    }

    func testAFewMinutesAndHoursAreCountedUp() {
        XCTAssertEqual(ReplyTime.label(since: replied, now: replied.addingTimeInterval(5 * 60), timeZone: utc), "5 min ago")
        XCTAssertEqual(ReplyTime.label(since: replied, now: replied.addingTimeInterval(3 * 3600), timeZone: utc), "3 hr ago")
    }

    func testAfterADayTheDateIsWrittenOutWithTheTime() {
        let label = ReplyTime.label(since: replied, now: replied.addingTimeInterval(26 * 3600), timeZone: utc)
        XCTAssertEqual(label, "Friday, October 9 at 3:42 PM")
    }
}

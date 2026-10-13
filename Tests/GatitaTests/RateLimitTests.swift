//
//  RateLimitTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// An HTTP 429 is waited out and sent again, a few times, instead of ending the reply.
final class RateLimitTests: XCTestCase {
    func testTheWaitIsReadFromTheHeaderOrTheBody() {
        XCTAssertEqual(RateLimit.delay(header: "7", body: ""), 7)
        XCTAssertEqual(RateLimit.delay(header: nil, body: #"{"error":"Rate limit exceeded","message":"Rate limit: 10 requests per minute","retryAfter":60}"#), 60)
        XCTAssertEqual(RateLimit.delay(header: nil, body: #"{"error": {"message": "slow down", "retry_after": 3.5}}"#), 3.5)
        XCTAssertEqual(RateLimit.delay(header: nil, body: #"{"retryAfter": "12"}"#), 12)
        XCTAssertNil(RateLimit.delay(header: nil, body: "Too many requests"))
    }

    func testTheHeaderWinsOverTheBody() {
        XCTAssertEqual(RateLimit.delay(header: "2", body: #"{"retryAfter": 60}"#), 2)
    }

    func testWaitsAreKeptToAShortRange() {
        XCTAssertEqual(RateLimit.waitSeconds(nil), RateLimit.defaultWait)
        XCTAssertEqual(RateLimit.waitSeconds(5), 5)
        XCTAssertEqual(RateLimit.waitSeconds(0), 1)
        XCTAssertNil(RateLimit.waitSeconds(3_600), "a wait of an hour is not waited out")
    }

    func testTheNoteCountsDown() {
        let now = Date()
        XCTAssertEqual(RateLimit.note(until: now.addingTimeInterval(41.2), now: now),
                       "Gatita's rate limit was reached. Trying again in 42 s.")
        XCTAssertEqual(RateLimit.note(until: now, now: now), "Gatita's rate limit was reached. Trying again now.")
    }
}

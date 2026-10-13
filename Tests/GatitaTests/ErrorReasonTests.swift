//
//  ErrorReasonTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// A reason is shown only when the server gave one. Nothing is invented.
final class ErrorReasonTests: XCTestCase {
    func testAReasonInTheErrorObjectIsRead() {
        XCTAssertEqual(GatitaError.serverReason(in: #"{"error":{"message":"Blocked by policy","type":"policy"}}"#), "Blocked by policy")
    }

    func testAPlainErrorStringIsRead() {
        XCTAssertEqual(GatitaError.serverReason(in: #"{"error":"Bad key"}"#), "Bad key")
    }

    func testAnErrorStringWithAMessageKeepsBoth() {
        XCTAssertEqual(GatitaError.serverReason(in: #"{"error":"Rate limit exceeded","message":"Rate limit: 10 requests per minute","retryAfter":60}"#),
                       "Rate limit exceeded (Rate limit: 10 requests per minute)")
    }

    func testABodyWithNoReasonGivesNone() {
        XCTAssertNil(GatitaError.serverReason(in: "<html>Gateway error</html>"))
        XCTAssertNil(GatitaError.serverReason(in: #"{"error":{}}"#))
        XCTAssertNil(GatitaError.serverReason(in: #"{"error":{"message":""}}"#))
    }
}

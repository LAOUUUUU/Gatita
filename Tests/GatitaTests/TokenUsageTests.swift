//
//  TokenUsageTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// Token counts for a reply: read from a streamed usage chunk, shown under the reply, and added up across tool rounds.
final class TokenUsageTests: XCTestCase {
    func testAUsageChunkIsRead() {
        let chunk = #"{"choices":[],"usage":{"prompt_tokens":14,"completion_tokens":22,"total_tokens":36}}"#
        XCTAssertEqual(TokenUsage.read(fromChunk: chunk), TokenUsage(promptTokens: 14, completionTokens: 22))
    }

    func testAChunkWithoutUsageGivesNothing() {
        XCTAssertNil(TokenUsage.read(fromChunk: #"{"choices":[{"delta":{"content":"hi"}}]}"#))
    }

    func testTheSummaryGroupsThousands() {
        XCTAssertEqual(TokenUsage(promptTokens: 1234, completionTokens: 567).summary, "1,234 in · 567 out")
    }

    func testUsageAddsUpAcrossToolRounds() {
        let total = TokenUsage(promptTokens: 10, completionTokens: 5)
            .adding(TokenUsage(promptTokens: 20, completionTokens: 7))
        XCTAssertEqual(total, TokenUsage(promptTokens: 30, completionTokens: 12))
    }

    func testAServerThatRejectsTheUsageOptionIsRecognised() {
        XCTAssertTrue(GatitaClient.rejectsStreamOptions(status: 400,
                                                        body: #"{"error":{"message":"Unknown parameter: stream_options"}}"#))
        XCTAssertFalse(GatitaClient.rejectsStreamOptions(status: 500, body: "stream_options"))
        XCTAssertFalse(GatitaClient.rejectsStreamOptions(status: 400, body: "bad model"))
    }

    func testOtherWaysOfRefusingTheUsageOptionAreRecognisedToo() {
        XCTAssertTrue(GatitaClient.rejectsStreamOptions(status: 422, body: #"{"detail":"extra field: stream_options"}"#))
        XCTAssertTrue(GatitaClient.rejectsStreamOptions(status: 400, body: #"{"error":"include_usage is not supported"}"#))
        XCTAssertTrue(GatitaClient.rejectsStreamOptions(status: 400, body: "Unrecognized request argument: Stream_Options"))
        XCTAssertFalse(GatitaClient.rejectsStreamOptions(status: 401, body: "stream_options"))
    }
}

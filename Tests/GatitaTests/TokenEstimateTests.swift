//
//  TokenEstimateTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// When the server reports no count, the reply's tokens are estimated from its text and labelled as estimates.
final class TokenEstimateTests: XCTestCase {
    func testAboutFourCharactersMakeAToken() {
        XCTAssertEqual(TokenEstimate.tokens(""), 0)
        XCTAssertEqual(TokenEstimate.tokens("abcd"), 1)
        XCTAssertEqual(TokenEstimate.tokens("abcde"), 2)
    }

    func testTheEstimateCountsTheSentTextAndTheReply() {
        let usage = TokenEstimate.usage(sentText: ["abcd", "abcdefgh"], reply: "abcdefghij")
        XCTAssertEqual(usage, TokenUsage(promptTokens: 3, completionTokens: 3, isEstimate: true))
    }

    func testAnEstimateSaysSo() {
        XCTAssertEqual(TokenUsage(promptTokens: 1, completionTokens: 2, isEstimate: true).summary,
                       "1 in · 2 out (estimated)")
        XCTAssertEqual(TokenUsage(promptTokens: 1, completionTokens: 2).summary, "1 in · 2 out")
    }

    func testUsageStillReadsWhenTheEstimateFlagIsMissing() throws {
        let saved = #"{"promptTokens":4,"completionTokens":6}"#
        let usage = try JSONDecoder().decode(TokenUsage.self, from: Data(saved.utf8))
        XCTAssertEqual(usage, TokenUsage(promptTokens: 4, completionTokens: 6))
    }

    func testTheUsageCommandCountsEstimatedReplies() {
        let estimated = UsageReport.Totals(promptTokens: 30, completionTokens: 12, replies: 2, estimatedReplies: 1)
        let text = UsageReport.text(thisChat: estimated, allChats: estimated)
        XCTAssertTrue(text.contains("(1 estimated)"), text)
    }
}

//
//  UsageReportTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// The /usage command: totals from the replies the server counted, and the text it shows.
final class UsageReportTests: XCTestCase {
    private let messages = [
        ChatMessage(role: "user", content: "hi"),
        ChatMessage(role: "assistant", content: "hello", usage: TokenUsage(promptTokens: 10, completionTokens: 5)),
        ChatMessage(role: "assistant", content: "no count"),
        ChatMessage(role: "assistant", content: "more", usage: TokenUsage(promptTokens: 20, completionTokens: 7)),
    ]

    func testTotalsAddUpOnlyTheCountedReplies() {
        XCTAssertEqual(UsageReport.totals(of: messages),
                       UsageReport.Totals(promptTokens: 30, completionTokens: 12, replies: 2))
    }

    func testTheTextShowsThisChatAndAllChats() {
        let chat = UsageReport.totals(of: messages)
        let text = UsageReport.text(thisChat: chat, allChats: chat)
        XCTAssertTrue(text.contains("This chat: 30 in · 12 out, from 2 replies"), text)
        XCTAssertTrue(text.contains("All saved chats: 30 in · 12 out, from 2 replies"), text)
    }

    func testWithNoCountsTheTextSaysSo() {
        let none = UsageReport.totals(of: [ChatMessage(role: "assistant", content: "x")])
        XCTAssertTrue(UsageReport.text(thisChat: none, allChats: none).contains("No token counts yet"))
    }

    func testOnlyTheUsageCommandIsRecognised() {
        XCTAssertTrue(UsageReport.isCommand("/usage"))
        XCTAssertTrue(UsageReport.isCommand("  /usage  "))
        XCTAssertFalse(UsageReport.isCommand("/usage please"))
        XCTAssertFalse(UsageReport.isCommand("what is usage"))
    }

    func testAChatHoldingOnlyANoticeIsNotWorthSaving() {
        XCTAssertFalse(ChatHistory.isWorthSaving([ChatMessage(role: "notice", content: "Usage")]))
        XCTAssertFalse(ChatHistory.isWorthSaving([]))
        XCTAssertTrue(ChatHistory.isWorthSaving([ChatMessage(role: "notice", content: "Usage"),
                                                 ChatMessage(role: "user", content: "hi")]))
    }
}

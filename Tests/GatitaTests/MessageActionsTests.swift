//
//  MessageActionsTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// The buttons under a reply: reply quotes it, fork keeps the chat up to it, and pin marks it.
final class MessageActionsTests: XCTestCase {
    private let messages = [
        ChatMessage(role: "user", content: "one"),
        ChatMessage(role: "assistant", content: "two"),
        ChatMessage(role: "user", content: "three"),
        ChatMessage(role: "assistant", content: "four"),
    ]

    func testReplyQuotesEachLine() {
        XCTAssertEqual(MessageActions.quote("first\nsecond"), "> first\n> second\n\n")
    }

    func testALongReplyIsQuotedOnlyForItsFirstLines() {
        let text = (1...10).map { "line \($0)" }.joined(separator: "\n")
        let quote = MessageActions.quote(text)
        XCTAssertTrue(quote.hasPrefix("> line 1\n"), quote)
        XCTAssertTrue(quote.contains("> line 6\n"), quote)
        XCTAssertFalse(quote.contains("line 7"), quote)
        XCTAssertTrue(quote.hasSuffix("> …\n\n"), quote)
    }

    func testForkKeepsTheChatUpToAndIncludingTheReply() {
        let kept = MessageActions.fork(messages, upTo: messages[1].id)
        XCTAssertEqual(kept?.map(\.id), [messages[0].id, messages[1].id])
    }

    func testForkOfAMissingMessageIsNil() {
        XCTAssertNil(MessageActions.fork(messages, upTo: UUID()))
    }

    func testAPinnedReplyStaysPinnedAndOldReplyHasNoPin() throws {
        let pinned = ChatMessage(role: "assistant", content: "keep", pinned: true)
        let loaded = try JSONDecoder().decode(ChatMessage.self, from: try JSONEncoder().encode(pinned))
        XCTAssertEqual(loaded.pinned, true)

        let plain = ChatMessage(role: "assistant", content: "plain")
        let loadedPlain = try JSONDecoder().decode(ChatMessage.self, from: try JSONEncoder().encode(plain))
        XCTAssertNil(loadedPlain.pinned)
    }
}

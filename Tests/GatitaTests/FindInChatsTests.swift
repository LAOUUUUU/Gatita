//
//  FindInChatsTests.swift
//  GatitaTests
//

import SwiftUI
import XCTest
@testable import Gatita

/// ⌘F in a chat, and the sidebar search that looks inside every message.
final class FindInChatsTests: XCTestCase {
    private func chat(_ title: String, _ reply: String) -> Conversation {
        Conversation(id: UUID(), updatedAt: Date(), messages: [ChatMessage(role: "user", content: title),
                                                               ChatMessage(role: "assistant", content: reply)])
    }

    // MARK: - Sidebar search

    func testTheSidebarSearchLooksInsideMessages() {
        let pasta = chat("Dinner ideas", "Try a lemon pasta with garlic.")
        let other = chat("Taxes", "File by April.")
        let sections = ChatSidebar.sections([pasta, other], search: "LEMON")
        XCTAssertEqual(sections.flatMap(\.chats).map(\.id), [pasta.id])
    }

    func testASnippetShowsTheWordsAroundTheMatch() {
        let long = String(repeating: "word ", count: 30) + "the secret ingredient is lemon zest " + String(repeating: "more ", count: 30)
        let snippet = ChatSearch.snippet(in: [ChatMessage(role: "assistant", content: long)], query: "lemon")
        XCTAssertNotNil(snippet)
        XCTAssertTrue(snippet!.contains("lemon zest"), snippet!)
        XCTAssertTrue(snippet!.hasPrefix("…") && snippet!.hasSuffix("…"), snippet!)
        XCTAssertLessThanOrEqual(snippet!.count, ChatSearch.snippetLength + 2)
    }

    func testErrorsAndNoticesAreNotSearched() {
        let messages = [ChatMessage(role: "error", content: "lemon failed"), ChatMessage(role: "notice", content: "lemon")]
        XCTAssertNil(ChatSearch.snippet(in: messages, query: "lemon"))
        XCTAssertNil(ChatSearch.snippet(in: [ChatMessage(role: "user", content: "x")], query: "  "), "a blank search finds nothing")
    }

    // MARK: - Find in the open chat

    func testEveryMatchInTheChatIsCountedInOrder() {
        let first = ChatMessage(role: "user", content: "Is Swift fast? swift!")
        let skipped = ChatMessage(role: "error", content: "swift")
        let second = ChatMessage(role: "assistant", content: "Yes, Swift is fast.")
        let found = FindInChat.matches(in: [first, skipped, second], query: "swift")
        XCTAssertEqual(found.map(\.messageID), [first.id, first.id, second.id])
        XCTAssertEqual(found.map(\.number), [0, 1, 0], "the number of the match inside its message")
        XCTAssertTrue(FindInChat.matches(in: [first], query: "").isEmpty)
    }

    func testNextAndPreviousGoRoundTheEnds() {
        XCTAssertEqual(FindInChat.step(from: 0, by: 1, count: 3), 1)
        XCTAssertEqual(FindInChat.step(from: 2, by: 1, count: 3), 0)
        XCTAssertEqual(FindInChat.step(from: 0, by: -1, count: 3), 2)
        XCTAssertEqual(FindInChat.step(from: 5, by: 1, count: 0), 0, "nothing found stays at 0")
    }

    func testMatchesAreHighlightedInTheText() {
        let text = FindInChat.highlighted(AttributedString("Swift is swift"), query: "SWIFT")
        let marked = text.runs.filter { $0.backgroundColor != nil }.map { String(text[$0.range].characters) }
        XCTAssertEqual(marked, ["Swift", "swift"])
        let plain = FindInChat.highlighted(AttributedString("nothing"), query: "")
        XCTAssertTrue(plain.runs.allSatisfy { $0.backgroundColor == nil })
    }
}

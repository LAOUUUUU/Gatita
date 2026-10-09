//
//  MarkdownAndReplyTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// How replies are shown (headings, lists, code) and the check for replies that leaked control tokens.
final class MarkdownAndReplyTests: XCTestCase {
    func testHeadingBulletsAndNumberedListsParse() {
        XCTAssertEqual(MarkdownBlocks.parse("## Folders"), [.heading(level: 2, text: "Folders")])
        XCTAssertEqual(MarkdownBlocks.parse("- one\n- two"), [.bullet(text: "one"), .bullet(text: "two")])
        XCTAssertEqual(MarkdownBlocks.parse("1. first\n2. second"),
                       [.numbered(number: 1, text: "first"), .numbered(number: 2, text: "second")])
    }

    func testParagraphsAndCodeBlocksKeepTheirText() {
        XCTAssertEqual(MarkdownBlocks.parse("**App/** — main app"), [.paragraph(text: "**App/** — main app")])
        XCTAssertEqual(MarkdownBlocks.parse("```swift\n# not a heading\nlet x = 1\n```"),
                       [.code(language: "swift", text: "# not a heading\nlet x = 1")])
        XCTAssertEqual(MarkdownBlocks.parse("Intro line\n\nNext para"),
                       [.paragraph(text: "Intro line"), .paragraph(text: "Next para")])
        XCTAssertEqual(MarkdownBlocks.parse("**App/** — text\n- item"),
                       [.paragraph(text: "**App/** — text"), .bullet(text: "item")])
    }

    func testAReplyWithALeakedControlTokenIsCaught() {
        XCTAssertTrue(ReplyCheck.isCorrupted("approximately<|close|> mechanism"))
        XCTAssertEqual(ReplyCheck.stripControlTokens("hi<|close|> there"), "hi there")
    }

    func testOrdinaryCodeWithAPipeIsNotCaught() {
        XCTAssertFalse(ReplyCheck.isCorrupted("let x = value |> transform(y)"))
    }
}

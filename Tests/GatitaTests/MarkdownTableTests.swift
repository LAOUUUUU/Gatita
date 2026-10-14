//
//  MarkdownTableTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// Markdown tables in a reply become one table block, with the text around them kept as text.
final class MarkdownTableTests: XCTestCase {
    func testATableBecomesOneBlock() {
        let source = "| # | Tool |\n|---|---|\n| 1 | list |\n| 2 | git |"
        XCTAssertEqual(MarkdownBlocks.parse(source),
                       [.table(header: ["#", "Tool"], rows: [["1", "list"], ["2", "git"]])])
    }

    func testTextAroundATableStaysText() {
        let source = "Intro\n| a | b |\n|:--|--:|\n| 1 | 2 |\nAfter"
        XCTAssertEqual(MarkdownBlocks.parse(source), [
            .paragraph(text: "Intro"),
            .table(header: ["a", "b"], rows: [["1", "2"]], alignments: [.leading, .trailing]),
            .paragraph(text: "After"),
        ])
    }

    func testAPipeLineWithoutASeparatorIsJustText() {
        XCTAssertEqual(MarkdownBlocks.parse("a | b"), [.paragraph(text: "a | b")])
    }
}

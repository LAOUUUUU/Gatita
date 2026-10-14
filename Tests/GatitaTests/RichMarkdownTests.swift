//
//  RichMarkdownTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// Plans, checklists, callouts, nested lists, aligned tables, and tables that can be drawn as charts.
final class RichMarkdownTests: XCTestCase {
    func testTaskLinesBecomeOneChecklist() {
        let blocks = MarkdownBlocks.parse("Plan:\n- [x] Read the code\n- [ ] Write the test\n  - [ ] Run it\n- [X] Ship")
        XCTAssertEqual(blocks, [
            .paragraph(text: "Plan:"),
            .checklist(items: [
                ChecklistItem(done: true, text: "Read the code", indent: 0),
                ChecklistItem(done: false, text: "Write the test", indent: 0),
                ChecklistItem(done: false, text: "Run it", indent: 1),
                ChecklistItem(done: true, text: "Ship", indent: 0),
            ]),
        ])
    }

    func testAChecklistCountsWhatIsDone() {
        let items = [ChecklistItem(done: true, text: "a", indent: 0), ChecklistItem(done: false, text: "b", indent: 0)]
        XCTAssertEqual(ChecklistItem.progress(items), "1 of 2 done")
    }

    func testNestedBulletsAndStepsKeepTheirDepth() {
        XCTAssertEqual(MarkdownBlocks.parse("- top\n  - inside\n    - deeper\n1. step\n   1. sub-step"), [
            .bullet(text: "top", indent: 0),
            .bullet(text: "inside", indent: 1),
            .bullet(text: "deeper", indent: 2),
            .numbered(number: 1, text: "step", indent: 0),
            .numbered(number: 1, text: "sub-step", indent: 1),
        ])
    }

    func testCalloutsAndQuotes() {
        XCTAssertEqual(MarkdownBlocks.parse("> [!TIP]\n> Use **batch** to save requests.\n> It runs ten calls."),
                       [.callout(kind: .tip, text: "Use **batch** to save requests.\nIt runs ten calls.")])
        XCTAssertEqual(MarkdownBlocks.parse("> [!warning] Back up first"), [.callout(kind: .warning, text: "Back up first")])
        XCTAssertEqual(MarkdownBlocks.parse("> Just a quote\n> on two lines"), [.callout(kind: nil, text: "Just a quote\non two lines")])
    }

    func testARuleSplitsTheReply() {
        XCTAssertEqual(MarkdownBlocks.parse("Above\n\n---\n\nBelow"), [.paragraph(text: "Above"), .rule, .paragraph(text: "Below")])
        XCTAssertEqual(MarkdownBlocks.parse("***"), [.rule])
    }

    func testTableColumnsKeepTheirAlignment() {
        let blocks = MarkdownBlocks.parse("| Item | Qty | Price |\n|:--|:-:|--:|\n| Tea | 2 | $4 |")
        XCTAssertEqual(blocks, [.table(header: ["Item", "Qty", "Price"], rows: [["Tea", "2", "$4"]],
                                      alignments: [.leading, .center, .trailing])])
    }

    func testATableWithNumbersCanBeDrawnAsAChart() throws {
        let spec = try XCTUnwrap(TableChart.spec(header: ["Month", "Sales ($)", "Note"],
                                                 rows: [["Jan", "$1,200", "slow"], ["Feb", "1 800", "ok"], ["Mar", "2.5k", "good"]]))
        XCTAssertEqual(spec.type, "bar")
        XCTAssertEqual(spec.title, "Sales ($) by Month")
        XCTAssertEqual(spec.points.map(\.label), ["Jan", "Feb", "Mar"])
        XCTAssertEqual(spec.points.map(\.value), [1200, 1800, 2500])
    }

    func testPercentagesAndLongSeriesBecomeLines() throws {
        let rows = (1...14).map { ["Day \($0)", "\($0 * 3)%"] }
        let spec = try XCTUnwrap(TableChart.spec(header: ["Day", "Done"], rows: rows))
        XCTAssertEqual(spec.type, "line", "many points read better as a line")
        XCTAssertEqual(spec.points.last?.value, 42)
    }

    func testATableWithoutNumbersHasNoChart() {
        XCTAssertNil(TableChart.spec(header: ["Tool", "Use"], rows: [["git", "history"], ["swift", "build"]]))
        XCTAssertNil(TableChart.spec(header: ["A", "B"], rows: [["x", "1"]]), "one row is not worth a chart")
    }

    func testTheModelIsToldWhatTheChatCanDraw() {
        let text = ReplyFormat.instructions
        XCTAssertTrue(text.contains("```chart"))
        XCTAssertTrue(text.contains("- [ ]"))
        XCTAssertTrue(text.contains("[!TIP]"))
        XCTAssertEqual(ReplyFormat.system(with: nil), text)
        XCTAssertEqual(ReplyFormat.system(with: "Be brief."), text + "\n\nBe brief.")
    }
}

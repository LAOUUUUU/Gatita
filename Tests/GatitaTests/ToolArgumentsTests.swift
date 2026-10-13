//
//  ToolArgumentsTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// A tool block's arguments are read as text, whatever JSON type the model used for each value.
final class ToolArgumentsTests: XCTestCase {
    func testNumbersAndBooleansBecomeText() {
        let args = ToolArguments.parse(#"{"tool":"task_status","wait":30,"ratio":2.5,"on":true,"off":false}"#)
        XCTAssertEqual(args, ["tool": "task_status", "wait": "30", "ratio": "2.5", "on": "true", "off": "false"])
    }

    func testAListBecomesOneItemPerLine() {
        XCTAssertEqual(ToolArguments.parse(#"{"paths":["a.swift","b.swift"]}"#)?["paths"], "a.swift\nb.swift")
    }

    func testNullAndNestedObjectsAreLeftOut() {
        let args = ToolArguments.parse(#"{"tool":"x","gone":null,"nested":{"k":1}}"#)
        XCTAssertEqual(args, ["tool": "x"])
    }

    func testTextThatIsNotAnObjectGivesNothing() {
        XCTAssertNil(ToolArguments.parse("not json"))
        XCTAssertNil(ToolArguments.parse("[1, 2]"))
    }

    func testAConnectorStillGetsNumbersAsText() {
        XCTAssertEqual(Connectors.stringArguments(#"{"number": 7}"#), ["number": "7"])
    }

    // MARK: - Slips the model makes

    func testRawLineBreaksAndTabsInsideATextAreRepaired() {
        let block = "{\"tool\": \"write_file\", \"path\": \"a.txt\", \"content\": \"line one\nline two\n\tindented\"}"
        let args = ToolArguments.parse(block)
        XCTAssertEqual(args?["tool"], "write_file")
        XCTAssertEqual(args?["content"], "line one\nline two\n\tindented")
    }

    func testEscapedLineBreaksAreLeftAlone() {
        XCTAssertEqual(ToolArguments.parse(#"{"tool": "write_file", "content": "a\nb"}"#)?["content"], "a\nb")
    }

    func testACodeFenceOrWordsAroundTheObjectAreDropped() {
        XCTAssertEqual(ToolArguments.parse("```json\n{\"tool\": \"read_file\", \"path\": \"a\"}\n```")?["path"], "a")
        XCTAssertEqual(ToolArguments.parse("Here: {\"tool\": \"read_file\", \"path\": \"a\"} done")?["tool"], "read_file")
    }

    func testATrailingCommaIsDroppedButOneInsideATextIsKept() {
        XCTAssertEqual(ToolArguments.parse(#"{"tool": "read_files", "paths": ["a", "b",],}"#)?["paths"], "a\nb")
        XCTAssertEqual(ToolArguments.parse(#"{"tool": "x", "content": "a,}",}"#)?["content"], "a,}")
    }

    func testTheOpenAIShapeWithNameAndArgumentsIsUnderstood() {
        let args = ToolArguments.parse(#"{"name": "read_file", "arguments": {"path": "README.md"}}"#)
        XCTAssertEqual(args?["tool"], "read_file")
        XCTAssertEqual(args?["path"], "README.md")
        XCTAssertNil(args?["arguments"])
    }

    func testArgumentsSentAsAJSONStringAreUnderstood() {
        let args = ToolArguments.parse(#"{"function": {"name": "read_file", "arguments": "{\"path\": \"a.swift\"}"}}"#)
        XCTAssertEqual(args?["tool"], "read_file")
        XCTAssertEqual(args?["path"], "a.swift")
    }

    func testAToolWithANameArgumentKeepsBoth() {
        let args = ToolArguments.parse(#"{"tool": "read_report", "name": "gatita.log"}"#)
        XCTAssertEqual(args?["tool"], "read_report")
        XCTAssertEqual(args?["name"], "gatita.log")
    }

    func testAnArgumentAtTheTopWinsOverTheSameOneNested() {
        XCTAssertEqual(ToolArguments.parse(#"{"tool": "read_file", "path": "top", "arguments": {"path": "nested"}}"#)?["path"], "top")
    }
}

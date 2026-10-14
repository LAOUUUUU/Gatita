//
//  ToolBatchTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// Tools that do several things in one request: batch runs up to 10 tool calls, and web_fetch reads up to 5 pages.
final class ToolBatchTests: XCTestCase {
    func testABatchIsSplitIntoItsCalls() throws {
        let calls = try ToolBatch.calls(in: #"{"tool": "batch", "calls": [{"tool": "read_file", "path": "a.swift"}, {"tool": "search_text", "query": "x"}]}"#)
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(ToolArguments.parse(calls[0]), ["tool": "read_file", "path": "a.swift"])
        XCTAssertEqual(ToolArguments.parse(calls[1])?["tool"], "search_text")
    }

    func testABatchWithRawLineBreaksIsRepairedToo() throws {
        let calls = try ToolBatch.calls(in: "{\"tool\": \"batch\", \"calls\": [{\"tool\": \"write_file\", \"path\": \"a.txt\", \"content\": \"one\ntwo\"}]}")
        XCTAssertEqual(ToolArguments.parse(calls[0])?["content"], "one\ntwo")
    }

    func testBadBatchesAreRefusedWithAReason() {
        XCTAssertThrowsError(try ToolBatch.calls(in: #"{"tool": "batch"}"#))
        XCTAssertThrowsError(try ToolBatch.calls(in: #"{"tool": "batch", "calls": []}"#))
        let eleven = Array(repeating: #"{"tool": "list_files", "path": "."}"#, count: 11).joined(separator: ",")
        XCTAssertThrowsError(try ToolBatch.calls(in: #"{"tool": "batch", "calls": [\#(eleven)]}"#))
        XCTAssertThrowsError(try ToolBatch.calls(in: #"{"tool": "batch", "calls": [{"tool": "batch", "calls": []}]}"#))
        XCTAssertThrowsError(try ToolBatch.calls(in: #"{"tool": "batch", "calls": [{"tool": "ask_user", "question": "?"}]}"#))
        XCTAssertThrowsError(try ToolBatch.calls(in: #"{"tool": "batch", "calls": [{"path": "no tool name"}]}"#))
    }

    func testResultsAreJoinedWithStartAndEndLines() {
        let text = ToolBatch.combine([("read_file", "let a = 1"), ("search_text", "error: query is empty")])
        XCTAssertTrue(text.hasPrefix("Ran 2 calls."), text)
        XCTAssertTrue(text.contains("===== result 1: read_file =====\nlet a = 1\n===== end of result 1 ====="), text)
        XCTAssertTrue(text.contains("===== result 2: search_text =====\nerror: query is empty\n===== end of result 2 ====="), text)
    }

    func testTheModelIsToldAboutBatch() {
        let tools = ProjectTools(root: nil, allowWrites: false, connectors: ["web"], allowsReports: false)
        XCTAssertTrue(tools.toolNames.contains("batch"))
        XCTAssertTrue(tools.instructions.contains(#""tool": "batch""#))
    }

    // MARK: - Several pages at once

    func testWebFetchTakesOneAddressOrSeveral() {
        XCTAssertEqual(WebFetch.addresses(["url": "https://a.example"]), ["https://a.example"])
        XCTAssertEqual(WebFetch.addresses(["urls": "https://a.example\nhttps://b.example\n\nhttps://a.example"]),
                       ["https://a.example", "https://b.example"])
        XCTAssertEqual(WebFetch.addresses(["urls": "https://a.example, https://b.example"]), ["https://a.example", "https://b.example"])
    }

    func testACommaInsideOneAddressDoesNotSplitIt() {
        XCTAssertEqual(WebFetch.addresses(["url": "https://en.wikipedia.org/wiki/Washington,_D.C."]),
                       ["https://en.wikipedia.org/wiki/Washington,_D.C."])
        XCTAssertEqual(WebFetch.addresses(["urls": "https://api.example/items?ids=1,2,3\nhttps://b.example"]),
                       ["https://api.example/items?ids=1,2,3", "https://b.example"])
    }

    func testSeveralPagesComeBackBetweenStartAndEndLines() {
        let text = WebFetch.combine([("https://a.example", .success("Page A")),
                                     ("https://b.example", .failure(ToolError("the page did not load")))])
        XCTAssertTrue(text.hasPrefix("Read 1 of 2 pages."), text)
        XCTAssertTrue(text.contains("===== start of https://a.example =====\nPage A\n===== end of https://a.example ====="), text)
        XCTAssertTrue(text.contains("===== start of https://b.example =====\nerror: the page did not load\n===== end of https://b.example ====="), text)
    }

    func testAPageThatDoesNotLoadSaysWhy() {
        XCTAssertEqual(WebFetch.statusError(404), "the page answered HTTP 404: it does not exist. Do not guess addresses; find the right one in a page that links to it, or ask the user.")
        XCTAssertEqual(WebFetch.statusError(503), "the page answered HTTP 503")
    }
}

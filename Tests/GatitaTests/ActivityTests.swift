//
//  ActivityTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// The status, time, and icon of a tool call, as the activity panel shows them.
final class ActivityTests: XCTestCase {
    func testAToolCallIsRunningUntilItHasAResult() {
        var call = ToolActivity(id: "t1", name: "run_command", arguments: "{}", result: nil)
        XCTAssertEqual(call.status, .running)
        call.result = "error: not allowed"
        XCTAssertEqual(call.status, .failed)
        call.result = "Swift version 6.4"
        XCTAssertEqual(call.status, .done)
    }

    func testTheTimeIsTheGapBetweenStartAndFinish() {
        let start = Date(timeIntervalSince1970: 1000)
        let call = ToolActivity(id: "t1", name: "run_command", arguments: "{}", result: "ok",
                                startedAt: start, finishedAt: start.addingTimeInterval(2))
        XCTAssertEqual(call.duration, 2)
    }

    func testEachKindOfToolHasItsIcon() {
        XCTAssertEqual(ToolActivity(id: "1", name: "run_command", arguments: "", result: nil).symbol, "terminal")
        XCTAssertEqual(ToolActivity(id: "2", name: "github_list_prs", arguments: "", result: nil).symbol, "arrow.triangle.pull")
        XCTAssertEqual(ToolActivity(id: "3", name: "unknown_tool", arguments: "", result: nil).symbol, "wrench.and.screwdriver")
    }

    func testDurationsReadWell() {
        XCTAssertEqual(ActivityFormat.duration(0.42), "0.4 s")
        XCTAssertEqual(ActivityFormat.duration(72), "1m 12s")
    }
}

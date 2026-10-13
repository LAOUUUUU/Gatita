//
//  TaskStatusTextTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// task_status waits for a running task and then tells the model whether to keep checking.
final class TaskStatusTextTests: XCTestCase {
    func testTheDefaultWaitIsTwentySeconds() {
        XCTAssertEqual(TaskStatusText.waitSeconds(nil), 20)
        XCTAssertEqual(TaskStatusText.waitSeconds("abc"), 20)
    }

    func testTheWaitIsKeptBetweenZeroAndSixtySeconds() {
        XCTAssertEqual(TaskStatusText.waitSeconds("5"), 5)
        XCTAssertEqual(TaskStatusText.waitSeconds("600"), 60)
        XCTAssertEqual(TaskStatusText.waitSeconds("-3"), 0)
    }

    func testARunningTaskSaysToCheckAgainAndAFinishedOneSaysToAnswer() {
        XCTAssertTrue(TaskStatusText.note(running: true).contains("still running"))
        XCTAssertTrue(TaskStatusText.note(running: false).contains("do not check it again"))
    }
}

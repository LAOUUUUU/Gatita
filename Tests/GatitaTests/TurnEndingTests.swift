//
//  TurnEndingTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// How a turn that made no tool call is judged: finished, or ended for no good reason.
final class TurnEndingTests: XCTestCase {
    private func classify(_ visible: String, finish: String? = "stop", cleanly: Bool = true,
                          unfinished: String? = nil, tools: Bool = true) -> TurnEnding? {
        TurnEnding.classify(visible: visible, finishReason: finish, endedCleanly: cleanly,
                            unfinishedBlock: unfinished, hasTools: tools)
    }

    func testAFinishedReplyHasNoProblem() {
        XCTAssertNil(classify("All done."))
        XCTAssertNil(classify("The files are listed below:\n\n```\na\n```"))
    }

    func testNothingWrittenIsEmpty() {
        XCTAssertEqual(classify("  \n"), .empty)
    }

    func testTheLengthLimitIsACutOff() {
        XCTAssertEqual(classify("half a sentence", finish: "length"), .cutOff)
    }

    func testAStartedToolBlockThatNeverFinishedIsACutOffToolCall() {
        XCTAssertEqual(classify("Let me look.", unfinished: "{\"tool\": \"list_fi"), .toolCallCutOff)
    }

    func testAConnectionThatClosedWithNoFinishReasonEndedEarly() {
        XCTAssertEqual(classify("partial", finish: nil, cleanly: false), .closedEarly)
    }

    func testATrailingColonIsUnfinishedOnlyWhenToolsExist() {
        XCTAssertEqual(classify("Checking the task:"), .unfinished)
        XCTAssertNil(classify("Checking the task:", tools: false))
    }

    func testEachProblemHasANudgeExceptAClosedConnection() {
        for ending in [TurnEnding.empty, .cutOff, .toolCallCutOff, .unfinished] {
            XCTAssertNotNil(ending.nudge(hasTools: true), "\(ending)")
        }
        XCTAssertNil(TurnEnding.closedEarly.nudge(hasTools: true))
    }

    func testTheEmptyNudgeOnlyMentionsToolsWhenThereAreSome() {
        XCTAssertTrue(TurnEnding.empty.nudge(hasTools: true)!.contains("tool block"))
        XCTAssertFalse(TurnEnding.empty.nudge(hasTools: false)!.contains("tool"))
    }

    func testOnlyAnUnfinishedReplyIsNotAnErrorOnceTheNudgesRunOut() {
        XCTAssertFalse(TurnEnding.unfinished.isErrorWhenExhausted)
        for ending in [TurnEnding.empty, .cutOff, .toolCallCutOff, .closedEarly] {
            XCTAssertTrue(ending.isErrorWhenExhausted, "\(ending)")
        }
    }

    func testAnObjectIsFoundWhenTheClosingTagIsMissing() {
        XCTAssertEqual(TurnEnding.completeObject(in: " {\"tool\": \"git_status\"}\n"), "{\"tool\": \"git_status\"}")
        XCTAssertEqual(TurnEnding.completeObject(in: "{\"a\": {\"b\": 1}} trailing text"), "{\"a\": {\"b\": 1}}")
    }

    func testBracesInsideStringsDoNotCount() {
        let text = "{\"content\": \"} not the end { \\\" still inside\"}"
        XCTAssertEqual(TurnEnding.completeObject(in: text), text)
    }

    func testACutOffObjectIsNotComplete() {
        XCTAssertNil(TurnEnding.completeObject(in: "{\"tool\": \"list_fi"))
        XCTAssertNil(TurnEnding.completeObject(in: "no object here"))
    }
}

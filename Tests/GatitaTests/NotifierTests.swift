//
//  NotifierTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// When a reply or a long task finishes while you are away, Gatita sends a system notification instead of a badge.
@MainActor
final class NotifierTests: XCTestCase {
    func testAFinishedReplyIsTitledByItsChatAndShowsItsFirstWords() {
        let note = Notifier.replyFinished(chatTitle: "Sales charts", reply: "## Summary\n\nSales **grew** 12% in March.\n\n```swift\nlet x = 1\n```")
        XCTAssertEqual(note.title, "Sales charts")
        XCTAssertEqual(note.body, "Summary")
    }

    func testALongReplyIsCutShort() {
        let note = Notifier.replyFinished(chatTitle: "Chat", reply: String(repeating: "word ", count: 100))
        XCTAssertLessThanOrEqual(note.body.count, Notifier.maxBodyLength + 1)
        XCTAssertTrue(note.body.hasSuffix("…"))
    }

    func testAnEmptyReplyStillSaysItFinished() {
        XCTAssertEqual(Notifier.replyFinished(chatTitle: "Chat", reply: "  ").body, "Gatita finished replying.")
    }

    func testAQuestionAndAFailureSaySo() {
        XCTAssertEqual(Notifier.question(chatTitle: "Chat", question: "Which file?").title, "Gatita asks: Chat")
        XCTAssertEqual(Notifier.question(chatTitle: "Chat", question: "Which file?").body, "Which file?")
        XCTAssertEqual(Notifier.failed(chatTitle: "Chat", reason: "No internet access.").title, "Gatita's reply failed: Chat")
    }

    func testACommandWaitingForYouSaysWhichOne() {
        let note = Notifier.commandWaiting(chatTitle: "Build fixes", command: "swift test --filter Foo")
        XCTAssertEqual(note.title, "Gatita wants to run a command")
        XCTAssertEqual(note.body, "swift test --filter Foo, in Build fixes. Allow or deny it in Gatita.")
    }

    func testABackgroundTaskSaysHowItEnded() {
        let done = Notifier.backgroundTaskFinished(command: "swift test", exitCode: 0, seconds: 125)
        XCTAssertEqual(done.title, "Background task finished")
        XCTAssertEqual(done.body, "swift test finished in 2m 5s.")
        let failed = Notifier.backgroundTaskFinished(command: "npm test", exitCode: 1, seconds: 3)
        XCTAssertEqual(failed.title, "Background task failed")
        XCTAssertEqual(failed.body, "npm test exited with code 1 after 3.0 s.")
    }

    func testTheRegistryReportsAFinishedBackgroundTask() async throws {
        let root = try makeProjectFixture(self)
        let registry = TaskRegistry()
        var reported: [String] = []
        registry.onTaskFinished = { note in reported.append(note.title) }
        let id = try registry.startBackground(["swift", "--version"], command: "swift --version", in: root)
        var waited = 0
        while registry.backgroundTask(id)?.status == .running, waited < 300 {
            try await Task.sleep(nanoseconds: 100_000_000)
            waited += 1
        }
        XCTAssertEqual(reported, ["Background task finished"])
        XCTAssertEqual(registry.runningCount, 0)
    }

    func testAStoppedTaskIsNotReported() async throws {
        let root = try makeProjectFixture(self)
        let registry = TaskRegistry()
        var reported = 0
        registry.onTaskFinished = { _ in reported += 1 }
        let id = try registry.startBackground(["swift", "build"], command: "swift build", in: root)
        XCTAssertEqual(registry.runningCount, 1)
        XCTAssertTrue(registry.stopBackground(id))
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(reported, 0, "you stopped it yourself, so there is nothing to tell you")
    }

    func testQuittingStopsEveryRunningBackgroundCommand() throws {
        let root = try makeProjectFixture(self)
        let registry = TaskRegistry()
        let first = try registry.startBackground(["swift", "build"], command: "swift build", in: root)
        let second = try registry.startBackground(["swift", "test"], command: "swift test", in: root)
        XCTAssertEqual(registry.stopAll(), 2)
        XCTAssertEqual(registry.backgroundTask(first)?.status, .stopped)
        XCTAssertEqual(registry.backgroundTask(second)?.status, .stopped)
        XCTAssertEqual(registry.stopAll(), 0, "nothing is left to stop")
    }
}

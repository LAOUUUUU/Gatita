//
//  TaskTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// Background commands, subagents, and the tools that control them.
final class TaskTests: XCTestCase {
    func testTheTaskToolsAreListedOnlyWhenTheyCanRun() throws {
        let root = try makeProjectFixture(self)
        let code = ProjectTools(root: root, allowWrites: false, allowCommands: true)
        XCTAssertTrue(code.instructions.contains("\"tool\": \"run_background\""))
        XCTAssertTrue(code.instructions.contains("\"tool\": \"spawn_agent\""))

        let subagent = code.readOnlyForSubagents()
        XCTAssertFalse(subagent.instructions.contains("\"tool\": \"spawn_agent\""))
        XCTAssertFalse(subagent.instructions.contains("\"tool\": \"run_background\""))

        let noCommands = ProjectTools(root: root, allowWrites: false)
        XCTAssertFalse(noCommands.instructions.contains("\"tool\": \"run_background\""))
        XCTAssertTrue(noCommands.instructions.contains("\"tool\": \"spawn_agent\""))

        let chat = ProjectTools(root: nil, allowWrites: false, allowCommands: true)
        XCTAssertFalse(chat.instructions.contains("spawn_agent"))
    }

    #if os(macOS)
    func testABackgroundCommandRunsToTheEnd() async throws {
        let root = try makeProjectFixture(self)
        let registry = TaskRegistry()
        let id = try registry.startBackground(["swift", "--version"], command: "swift --version", in: root)
        XCTAssertEqual(registry.backgroundTask(id)?.status, .running)

        var waited = 0
        while registry.backgroundTask(id)?.status == .running, waited < 300 {
            try await Task.sleep(nanoseconds: 100_000_000)
            waited += 1
        }
        let task = registry.backgroundTask(id)
        XCTAssertEqual(task?.status, .done)
        XCTAssertEqual(task?.exitCode, 0)
        XCTAssertTrue(task?.output.contains("Swift version") == true, task?.output ?? "")
    }
    #endif
}

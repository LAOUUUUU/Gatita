//
//  ToolThreadingTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// Tools run off the main actor, so a long command or a slow page never freezes the window.
@MainActor
final class ToolThreadingTests: XCTestCase {
    func testALongCommandDoesNotBlockTheMainActor() async throws {
        let root = try makeProjectFixture(self)
        let tools = ProjectTools(root: root, allowWrites: false, allowCommands: true, commands: [["sleep"]])
        let started = Date()
        let call = Task { @MainActor in
            await tools.execute(name: "run_command", arguments: #"{"tool": "run_command", "command": "sleep 1"}"#)
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        let waited = Date().timeIntervalSince(started)
        let result = await call.value

        XCTAssertLessThan(waited, 0.8, "the main actor was blocked while the command ran")
        XCTAssertEqual(result, "(no output)")
    }

    func testLoadingTheRepoStateDoesNotBlockTheMainActor() async throws {
        let root = try makeProjectFixture(self)
        // A stand-in for git that takes a second and then fails.
        let slowGit = root.appendingPathComponent("slow-git.sh")
        try "#!/bin/sh\nsleep 1\nexit 1\n".write(to: slowGit, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: slowGit.path)
        let started = Date()
        let load = Task { @MainActor in
            await RepoStateLoader.load(for: root, git: slowGit)
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        let waited = Date().timeIntervalSince(started)
        let state = await load.value

        XCTAssertLessThan(waited, 0.8, "the main actor was blocked while git ran")
        XCTAssertFalse(state.isRepo)
    }
}

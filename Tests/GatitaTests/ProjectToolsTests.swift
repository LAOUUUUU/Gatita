//
//  ProjectToolsTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// File tools stay inside the project, never touch .git, and write only when allowed.
final class ProjectToolsTests: XCTestCase {
    private var root: URL!
    private var readOnly: ProjectTools!

    override func setUpWithError() throws {
        root = try makeProjectFixture(self)
        readOnly = ProjectTools(root: root, allowWrites: false)
    }

    func testPathsCannotLeaveTheProjectOrTouchGit() {
        XCTAssertTrue(readOnly.run(name: "read_file", arguments: #"{"path": "../../../etc/hosts"}"#).hasPrefix("error:"))
        XCTAssertTrue(readOnly.run(name: "read_file", arguments: #"{"path": "/etc/hosts"}"#).hasPrefix("error:"))
        XCTAssertTrue(readOnly.run(name: "read_file", arguments: #"{"path": ".git/config"}"#).hasPrefix("error:"))
        XCTAssertFalse(readOnly.run(name: "list_files", arguments: #"{"path": "."}"#).contains(".git"))
        XCTAssertEqual(readOnly.run(name: "read_file", arguments: #"{"path": "App/GatitaApp.swift"}"#), "let app = 1\n")
    }

    func testWritesAreRefusedUnlessAllowed() throws {
        let target = root.appendingPathComponent("App/New.swift")
        let refused = readOnly.run(name: "write_file", arguments: #"{"path": "App/New.swift", "content": "x"}"#)
        XCTAssertTrue(refused.hasPrefix("error:"), refused)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))

        let writable = ProjectTools(root: root, allowWrites: true)
        XCTAssertEqual(writable.run(name: "write_file", arguments: #"{"path": "App/New.swift", "content": "let n = 2\n"}"#),
                       "wrote App/New.swift")
        XCTAssertEqual(writable.run(name: "edit_file", arguments: #"{"path": "App/New.swift", "old_text": "let n = 2", "new_text": "let n = 3"}"#),
                       "edited App/New.swift")
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "let n = 3\n")
    }

    func testEditRefusesAmbiguousText() throws {
        try "dup\ndup\n".write(to: root.appendingPathComponent("App/Dup.swift"), atomically: true, encoding: .utf8)
        let writable = ProjectTools(root: root, allowWrites: true)
        let ambiguous = writable.run(name: "edit_file", arguments: #"{"path": "App/Dup.swift", "old_text": "dup", "new_text": "x"}"#)
        XCTAssertTrue(ambiguous.hasPrefix("error:"), ambiguous)
    }

    func testFileTreeListsFoldersFirstWithoutGit() throws {
        let tree = try readOnly.tree()
        XCTAssertEqual(tree.first { $0.name == "App" }?.children?.contains { $0.name == "GatitaApp.swift" }, true)
        XCTAssertEqual(tree.first?.isDirectory, true)
        XCTAssertFalse(tree.contains { $0.name == ".git" })
        let path = tree.first { $0.name == "App" }?.children?.first { $0.name == "GatitaApp.swift" }?.path
        XCTAssertEqual(path, "App/GatitaApp.swift")
        XCTAssertEqual(try readOnly.readText("App/GatitaApp.swift"), "let app = 1\n")
        XCTAssertThrowsError(try readOnly.readText(".git/config"))
    }

    func testSearchFindsLinesAndSkipsGit() {
        let hit = readOnly.run(name: "search_text", arguments: #"{"query": "let app"}"#)
        XCTAssertTrue(hit.contains("App/GatitaApp.swift:1:let app = 1"), hit)
        XCTAssertEqual(readOnly.run(name: "search_text", arguments: #"{"query": "secret"}"#), "(no matches)")
        XCTAssertEqual(readOnly.run(name: "search_text", arguments: #"{"query": "zzz-nothing"}"#), "(no matches)")
    }

    func testGitStatusRefusesAFolderThatIsNotARepo() {
        XCTAssertTrue(readOnly.run(name: "git_status", arguments: "{}").hasPrefix("error:"))
    }

    func testTheModelIsToldAboutAskUser() {
        XCTAssertTrue(readOnly.instructions.contains("ask_user"))
        XCTAssertTrue(readOnly.instructions.contains("\"tool\": \"read_file\""))
    }
}

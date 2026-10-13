//
//  ToolHelpTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// When a tool call goes wrong, the error tells the model how to get it right, and the tools that find files
/// spare it from guessing paths.
final class ToolHelpTests: XCTestCase {
    private var root: URL!
    private var readOnly: ProjectTools!

    override func setUpWithError() throws {
        root = try makeProjectFixture(self)
        readOnly = ProjectTools(root: root, allowWrites: false)
    }

    // MARK: - Errors that say what to do

    func testABlockThatIsNotJSONSaysHowToWriteOne() {
        let result = readOnly.run(name: "unknown", arguments: "read the file please")
        XCTAssertTrue(result.hasPrefix("error: the tool block is not valid JSON"), result)
        XCTAssertTrue(result.contains(#"{"tool": "#), result)
    }

    func testAnUnknownToolListsTheToolsThatExist() {
        let result = readOnly.run(name: "delete_everything", arguments: #"{"tool": "delete_everything"}"#)
        XCTAssertTrue(result.hasPrefix("error: unknown tool delete_everything."), result)
        XCTAssertTrue(result.contains("read_file"), result)
        XCTAssertTrue(result.contains("find_files"), result)
        XCTAssertFalse(result.contains("write_file"), "writes are off, so write_file is not offered: \(result)")
    }

    func testABlockWithNoToolFieldSaysSo() {
        let result = readOnly.run(name: "unknown", arguments: #"{"path": "README.md"}"#)
        XCTAssertTrue(result.hasPrefix(#"error: the tool block has no "tool" field"#), result)
    }

    func testARefusedCommandListsTheAllowedOnes() {
        let tools = ProjectTools(root: root, allowWrites: false, allowCommands: true)
        let result = tools.run(name: "run_command", arguments: #"{"command": "ls -la"}"#)
        XCTAssertTrue(result.hasPrefix("error:"), result)
        XCTAssertTrue(result.contains("swift build"), result)
    }

    func testTurnedOffWritesPointAtTheSetting() {
        let result = readOnly.run(name: "write_file", arguments: #"{"path": "a.txt", "content": "x"}"#)
        XCTAssertTrue(result.contains("turned off"), result)
        XCTAssertFalse(result.contains("GATITA_ALLOW_WRITES"), result)
    }

    func testAMissingFileSuggestsFilesWithTheSameName() {
        let result = readOnly.run(name: "read_file", arguments: #"{"path": "GatitaApp.swift"}"#)
        XCTAssertTrue(result.hasPrefix("error: not a file: GatitaApp.swift"), result)
        XCTAssertTrue(result.contains("App/GatitaApp.swift"), result)
    }

    // MARK: - The tool names

    func testTheToolNamesFollowWhatIsTurnedOn() {
        XCTAssertTrue(readOnly.toolNames.contains("list_files"))
        XCTAssertTrue(readOnly.toolNames.contains("find_files"))
        XCTAssertFalse(readOnly.toolNames.contains("write_file"))
        XCTAssertFalse(readOnly.toolNames.contains("run_command"))
        let writable = ProjectTools(root: root, allowWrites: true, allowCommands: true)
        XCTAssertTrue(writable.toolNames.contains("edit_file"))
        XCTAssertTrue(writable.toolNames.contains("run_command"))
        let web = ProjectTools(root: nil, allowWrites: false, connectors: ["web"], allowsReports: false)
        XCTAssertEqual(Set(web.toolNames), ["web_fetch", "web_curl"])
    }

    // MARK: - find_files and search_text

    func testFindFilesMatchesPartOfANameInAnyCase() throws {
        try "x".write(to: root.appendingPathComponent("App/gatita-notes.md"), atomically: true, encoding: .utf8)
        let result = readOnly.run(name: "find_files", arguments: #"{"tool": "find_files", "name": "GATITA"}"#)
        XCTAssertEqual(result, "App/GatitaApp.swift\nApp/gatita-notes.md")
        XCTAssertEqual(readOnly.run(name: "find_files", arguments: #"{"name": "config"}"#), "(no matches)", ".git is never searched")
    }

    func testSearchCanIgnoreCaseAndStayInOneFolder() throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Other"), withIntermediateDirectories: true)
        try "LET APP = 2\n".write(to: root.appendingPathComponent("Other/Copy.swift"), atomically: true, encoding: .utf8)

        XCTAssertEqual(readOnly.run(name: "search_text", arguments: #"{"query": "let app"}"#), "App/GatitaApp.swift:1:let app = 1")
        XCTAssertEqual(readOnly.run(name: "search_text", arguments: #"{"query": "let app", "ignore_case": true, "path": "Other"}"#),
                       "Other/Copy.swift:1:LET APP = 2")
        XCTAssertTrue(readOnly.run(name: "search_text", arguments: #"{"query": "x", "path": "../"}"#).hasPrefix("error:"))
    }

    // MARK: - The same call twice

    func testTheSameCallTwiceInARowIsNoticed() {
        XCTAssertTrue(ToolRepeat.isRepeat(#"{"tool": "read_file", "path": "a"}"#, of: #"{ "path": "a", "tool": "read_file" }"#))
        XCTAssertFalse(ToolRepeat.isRepeat(#"{"tool": "read_file", "path": "a"}"#, of: #"{"tool": "read_file", "path": "b"}"#))
        XCTAssertFalse(ToolRepeat.isRepeat(#"{"tool": "read_file", "path": "a"}"#, of: nil))
    }
}

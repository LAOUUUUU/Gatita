//
//  DiffTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// The diff Gatita shows for a file change, and the preview that is made before a write or edit runs.
final class DiffTests: XCTestCase {
    func testIdenticalTextHasNoDiff() {
        XCTAssertEqual(LineDiff.lines(from: "a\nb\n", to: "a\nb\n"), [])
    }

    func testAChangedLineShowsAsRemovedThenAdded() {
        let lines = LineDiff.lines(from: "x\ny\nz", to: "x\nY\nz")
        XCTAssertEqual(lines, [
            DiffLine(kind: .same, text: "x"),
            DiffLine(kind: .removed, text: "y"),
            DiffLine(kind: .added, text: "Y"),
            DiffLine(kind: .same, text: "z"),
        ])
    }

    func testAddedLinesAreCounted() {
        let change = FileChange(path: "a.txt", lines: LineDiff.lines(from: "one\n", to: "one\ntwo\nthree\n"))
        XCTAssertEqual(change.added, 2)
        XCTAssertEqual(change.removed, 0)
    }

    func testANewFileIsAllAdded() {
        let lines = LineDiff.lines(from: "", to: "first\nsecond\n")
        XCTAssertTrue(lines.allSatisfy { $0.kind == .added })
        XCTAssertEqual(lines.count, 2)
    }

    func testAnEditPreviewShowsTheLinesItWouldChange() throws {
        let root = try makeProjectFixture(self)
        let tools = ProjectTools(root: root, allowWrites: false)
        let change = tools.changePreview(name: "edit_file",
                                         arguments: #"{"path": "App/GatitaApp.swift", "old_text": "let app = 1", "new_text": "let app = 2"}"#)
        XCTAssertEqual(change?.path, "App/GatitaApp.swift")
        XCTAssertEqual(change?.removed, 1)
        XCTAssertEqual(change?.added, 1)
        // The preview changes nothing on disk.
        XCTAssertEqual(try tools.readText("App/GatitaApp.swift"), "let app = 1\n")
    }

    func testAWritePreviewToANewFileIsAllAdded() throws {
        let root = try makeProjectFixture(self)
        let tools = ProjectTools(root: root, allowWrites: false)
        let change = tools.changePreview(name: "write_file", arguments: #"{"path": "App/New.swift", "content": "let n = 3\n"}"#)
        XCTAssertEqual(change?.added, 1)
        XCTAssertEqual(change?.removed, 0)
    }

    func testAnEditThatWouldFailHasNoPreview() throws {
        let root = try makeProjectFixture(self)
        try "dup\ndup\n".write(to: root.appendingPathComponent("App/Dup.swift"), atomically: true, encoding: .utf8)
        let tools = ProjectTools(root: root, allowWrites: false)
        XCTAssertNil(tools.changePreview(name: "edit_file", arguments: #"{"path": "App/Dup.swift", "old_text": "dup", "new_text": "x"}"#))
        XCTAssertNil(tools.changePreview(name: "read_file", arguments: #"{"path": "App/GatitaApp.swift"}"#))
    }
}

//
//  ReadFilesTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// read_files: several project files in one call, returned as one Markdown document.
final class ReadFilesTests: XCTestCase {
    private func tools(_ files: [String: String] = [:]) throws -> ProjectTools {
        let root = try makeProjectFixture(self)
        try "# Notes\n".write(to: root.appendingPathComponent("App/Notes.md"), atomically: true, encoding: .utf8)
        for (name, text) in files {
            try text.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        return ProjectTools(root: root, allowWrites: false)
    }

    func testSeveralFilesComeBackAsOneMarkdownDocument() throws {
        let output = try tools().run(name: "read_files", arguments: #"{"paths": "App/GatitaApp.swift\nApp/Notes.md"}"#)
        XCTAssertTrue(output.hasPrefix("Read 2 of 2 files."), output)
        XCTAssertTrue(output.contains("## App/GatitaApp.swift\n\n```swift\nlet app = 1\n```"), output)
        XCTAssertTrue(output.contains("## App/Notes.md\n\n```md\n# Notes\n```"), output)
    }

    func testAListOfPathsWorksToo() throws {
        let output = try tools().run(name: "read_files", arguments: #"{"paths": ["App/GatitaApp.swift", "App/Notes.md"]}"#)
        XCTAssertTrue(output.contains("let app = 1") && output.contains("# Notes"), output)
    }

    func testCommaSeparatedPathsWork() throws {
        let output = try tools().run(name: "read_files", arguments: #"{"paths": "App/GatitaApp.swift, App/Notes.md"}"#)
        XCTAssertTrue(output.hasPrefix("Read 2 of 2 files."), output)
    }

    func testOneBadPathDoesNotStopTheOthers() throws {
        let output = try tools().run(name: "read_files",
                                     arguments: #"{"paths": "App/GatitaApp.swift\n../outside.txt\n.git/config\nApp/Missing.swift"}"#)
        XCTAssertTrue(output.hasPrefix("Read 1 of 4 files."), output)
        XCTAssertTrue(output.contains("let app = 1"), output)
        XCTAssertTrue(output.contains("## ../outside.txt\n\nerror: path is outside the project"), output)
        XCTAssertTrue(output.contains("## .git/config\n\nerror: refusing to touch .git"), output)
        XCTAssertFalse(output.contains("secret"), output)
    }

    func testTooManyFilesAreRefused() throws {
        let paths = (1...21).map { "App/f\($0).swift" }.joined(separator: "\\n")
        let output = try tools().run(name: "read_files", arguments: #"{"paths": "\#(paths)"}"#)
        XCTAssertTrue(output.hasPrefix("error:"), output)
    }

    func testNoPathsIsAnError() throws {
        XCTAssertTrue(try tools().run(name: "read_files", arguments: #"{"paths": "  "}"#).hasPrefix("error:"))
        XCTAssertTrue(try tools().run(name: "read_files", arguments: "{}").hasPrefix("error:"))
    }

    func testAFileThatHoldsBackticksCannotCloseItsFenceEarly() throws {
        let tools = try tools(["Fenced.md": "```swift\nlet x = 1\n```\n"])
        let output = tools.run(name: "read_files", arguments: #"{"paths": "Fenced.md"}"#)
        XCTAssertTrue(output.contains("````md\n```swift\nlet x = 1\n```\n````"), output)
    }

    func testTheSameFileNamedTwiceIsReadOnce() throws {
        let output = try tools().run(name: "read_files", arguments: #"{"paths": "App/GatitaApp.swift\n./App/GatitaApp.swift"}"#)
        XCTAssertTrue(output.hasPrefix("Read 1 of 1 files."), output)
        XCTAssertEqual(output.components(separatedBy: "let app = 1").count - 1, 1, output)
    }

    func testTheTotalIsCappedAndLaterFilesAreSkipped() throws {
        let big = String(repeating: "a", count: 60_000)
        let tools = try tools(["One.txt": big, "Two.txt": big, "Three.txt": big])
        let output = tools.run(name: "read_files", arguments: #"{"paths": "One.txt\nTwo.txt\nThree.txt"}"#)
        XCTAssertTrue(output.contains("truncated: the 100000-character limit"), String(output.prefix(300)))
        XCTAssertTrue(output.contains("## Three.txt\n\nskipped: the 100000-character limit"), String(output.suffix(300)))
        XCTAssertLessThan(output.count, 101_000)
    }

    func testTheToolIsOfferedOnlyWithAProjectFolder() throws {
        XCTAssertTrue(try tools().instructions.contains("\"tool\": \"read_files\""))
        XCTAssertFalse(ProjectTools(root: nil, allowWrites: false).instructions.contains("read_files"))
    }

    func testThePathListKeepsOrderAndDropsBlanksAndRepeats() {
        XCTAssertEqual(ReadFiles.pathList("a.swift\n\n b.swift \na.swift\n"), ["a.swift", "b.swift"])
        XCTAssertEqual(ReadFiles.pathList("a.swift, b.swift"), ["a.swift", "b.swift"])
        // With one path per line, a comma belongs to the name.
        XCTAssertEqual(ReadFiles.pathList("Data, final.csv\nb.swift"), ["Data, final.csv", "b.swift"])
    }
}

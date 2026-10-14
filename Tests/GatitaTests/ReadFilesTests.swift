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
        XCTAssertTrue(output.contains("## App/GatitaApp.swift\n\n===== start of App/GatitaApp.swift =====\n```swift\nlet app = 1\n```\n===== end of App/GatitaApp.swift ====="), output)
        XCTAssertTrue(output.contains("## App/Notes.md\n\n===== start of App/Notes.md =====\n```md\n# Notes\n```\n===== end of App/Notes.md ====="), output)
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

    // MARK: - Folders and patterns

    private func project() throws -> (ProjectTools, URL) {
        let root = try makeProjectFixture(self)
        try "# Notes\n".write(to: root.appendingPathComponent("App/Notes.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Sub/Deep"), withIntermediateDirectories: true)
        try "let deep = 2\n".write(to: root.appendingPathComponent("Sub/Deep/Deep.swift"), atomically: true, encoding: .utf8)
        try Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0xFF]).write(to: root.appendingPathComponent("App/logo.png"))
        return (ProjectTools(root: root, allowWrites: false), root)
    }

    func testAPatternReadsEveryMatchingFile() throws {
        let output = try project().0.run(name: "read_files", arguments: #"{"paths": "App/*.swift"}"#)
        XCTAssertTrue(output.hasPrefix("Read 1 of 1 files."), output)
        XCTAssertTrue(output.contains("let app = 1"), output)
        XCTAssertFalse(output.contains("# Notes"), output)
    }

    func testADoubleStarLooksInEveryFolderButNeverGit() throws {
        let output = try project().0.run(name: "read_files", arguments: #"{"paths": "**/*.swift"}"#)
        XCTAssertTrue(output.hasPrefix("Read 2 of 2 files."), output)
        XCTAssertTrue(output.contains("let app = 1") && output.contains("let deep = 2"), output)
        XCTAssertFalse(output.contains("secret"), output)
    }

    func testAFolderReadsItsTextFilesAndSkipsTheRest() throws {
        let output = try project().0.run(name: "read_files", arguments: #"{"paths": "App/\nSub"}"#)
        XCTAssertTrue(output.hasPrefix("Read 3 of 3 files."), output)
        XCTAssertTrue(output.contains("# Notes") && output.contains("let deep = 2"), output)
        XCTAssertTrue(output.contains("Skipped 1 file that is not text: App/logo.png"), output)
        XCTAssertFalse(output.contains("## App/logo.png"), output)
    }

    func testAPatternThatMatchesNothingSaysSo() throws {
        let output = try project().0.run(name: "read_files", arguments: #"{"paths": "Nope/*.swift\nApp/GatitaApp.swift"}"#)
        XCTAssertTrue(output.contains("## Nope/*.swift\n\nno files match"), output)
        XCTAssertTrue(output.contains("let app = 1"), output)
    }

    func testAPatternThatMatchesTooManyReadsTheFirstOnesAndSaysHowManyAreLeft() throws {
        let (tools, root) = try project()
        for number in 1...25 {
            try "\(number)\n".write(to: root.appendingPathComponent(String(format: "App/n%02d.txt", number)), atomically: true, encoding: .utf8)
        }
        let output = tools.run(name: "read_files", arguments: #"{"paths": "App/*.txt"}"#)
        XCTAssertTrue(output.hasPrefix("Read 20 of 20 files."), String(output.prefix(200)))
        XCTAssertTrue(output.contains("5 more files matched"), String(output.suffix(300)))
        XCTAssertTrue(output.contains("App/n20.txt") && !output.contains("## App/n21.txt"), String(output.suffix(300)))
    }

    func testPatternsCannotLeaveTheProject() throws {
        let output = try project().0.run(name: "read_files", arguments: #"{"paths": "../*"}"#)
        XCTAssertTrue(output.contains("error:"), output)
    }

    func testGlobsBecomeAnchoredExpressions() {
        XCTAssertTrue(ReadFiles.matches("App/A.swift", pattern: "App/*.swift"))
        XCTAssertFalse(ReadFiles.matches("App/Sub/A.swift", pattern: "App/*.swift"))
        XCTAssertTrue(ReadFiles.matches("App/Sub/A.swift", pattern: "App/**/*.swift"))
        XCTAssertTrue(ReadFiles.matches("App/A.swift", pattern: "App/**/*.swift"))
        XCTAssertTrue(ReadFiles.matches("a.c", pattern: "?.c"))
        XCTAssertFalse(ReadFiles.matches("a+c", pattern: "a.c"), "a dot is a dot, not any character")
    }

    func testAPathWithBracketsIsReadAsItIsWritten() throws {
        let (tools, root) = try project()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("web/[id]"), withIntermediateDirectories: true)
        try "export default 1\n".write(to: root.appendingPathComponent("web/[id]/page.tsx"), atomically: true, encoding: .utf8)
        let file = tools.run(name: "read_files", arguments: #"{"paths": "web/[id]/page.tsx"}"#)
        XCTAssertTrue(file.hasPrefix("Read 1 of 1 files.") && file.contains("export default 1"), file)
        let folder = tools.run(name: "read_files", arguments: #"{"paths": "web/[id]"}"#)
        XCTAssertTrue(folder.hasPrefix("Read 1 of 1 files.") && folder.contains("export default 1"), folder)
    }

    func testFoldersAndPatternsLeaveOutHiddenFilesUnlessTheyNameThem() throws {
        let (tools, root) = try project()
        try "API_KEY=abc\n".write(to: root.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".github"), withIntermediateDirectories: true)
        try "on: push\n".write(to: root.appendingPathComponent(".github/ci.yml"), atomically: true, encoding: .utf8)
        let everything = tools.run(name: "read_files", arguments: #"{"paths": "."}"#)
        XCTAssertTrue(everything.contains("let app = 1"), everything)
        XCTAssertFalse(everything.contains("API_KEY") || everything.contains("on: push"), everything)
        let named = tools.run(name: "read_files", arguments: #"{"paths": ".github/*.yml\n**/.env"}"#)
        XCTAssertTrue(named.contains("on: push") && named.contains("API_KEY"), named)
    }

    func testABrokenPatternSaysSoInsteadOfFindingNothing() throws {
        let output = try project().0.run(name: "read_files", arguments: #"{"paths": "App/[a\nApp/GatitaApp.swift"}"#)
        XCTAssertTrue(output.contains("## App/[a\n\nerror: App/[a is not a valid pattern"), output)
        XCTAssertTrue(output.contains("let app = 1"), "the other entries are still read")
        XCTAssertFalse(ReadFiles.isValidPattern("App/[a"))
        XCTAssertTrue(ReadFiles.isValidPattern("App/[ab]*.swift"))
    }
}

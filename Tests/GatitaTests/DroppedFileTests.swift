//
//  DroppedFileTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// Files dropped on the prompt box: text files are read, and folders, binary files, and very large files are refused.
final class DroppedFileTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        folder = temporaryFolder(self, name: "gatita-drop")
    }

    func testATextFileIsRead() throws {
        let url = folder.appendingPathComponent("notes.txt")
        try "hello there".write(to: url, atomically: true, encoding: .utf8)
        let file = try DroppedFile.read(url)
        XCTAssertEqual(file.name, "notes.txt")
        XCTAssertEqual(file.text, "hello there")
    }

    func testAFolderIsRefused() throws {
        let subfolder = folder.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
        XCTAssertThrowsError(try DroppedFile.read(subfolder)) { error in
            XCTAssertEqual(error as? DroppedFile.ReadError, .notAFile("Sources"))
        }
    }

    func testABinaryFileIsRefused() throws {
        let url = folder.appendingPathComponent("image.bin")
        try Data([0xFF, 0xFE, 0x00, 0x81]).write(to: url)
        XCTAssertThrowsError(try DroppedFile.read(url)) { error in
            XCTAssertEqual(error as? DroppedFile.ReadError, .notText("image.bin"))
        }
    }

    func testAFileOverTheLimitIsRefused() throws {
        let url = folder.appendingPathComponent("big.txt")
        try Data(repeating: 0x61, count: DroppedFile.maxBytes + 1).write(to: url)
        XCTAssertThrowsError(try DroppedFile.read(url)) { error in
            XCTAssertEqual(error as? DroppedFile.ReadError, .tooLarge("big.txt", DroppedFile.maxBytes))
        }
    }

    func testLongPasteBecomesNumberedMarkdownFiles() {
        let first = DroppedFile.pasted("first long text", among: [])
        XCTAssertEqual(first.name, "Pasted text.md")
        XCTAssertEqual(first.kind, "Markdown")
        let second = DroppedFile.pasted("second", among: [first])
        XCTAssertEqual(second.name, "Pasted text 2.md")
        XCTAssertEqual(second.text, "second")
    }

    func testTheCardNamesTheFileType() {
        XCTAssertEqual(DroppedFile(name: "notes.md", text: "").kind, "Markdown")
        XCTAssertEqual(DroppedFile(name: "main.swift", text: "").kind, "SWIFT")
        XCTAssertEqual(DroppedFile(name: "README", text: "").kind, "Text")
    }

    func testAPictureIsReadAsAnImage() throws {
        let url = folder.appendingPathComponent("shot.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: url)
        let file = try DroppedFile.read(url)
        XCTAssertEqual(file.image?.name, "shot.png")
        XCTAssertEqual(file.image?.mimeType, "image/png")
        XCTAssertEqual(file.image?.data, Data([0x89, 0x50, 0x4E, 0x47]))
        XCTAssertEqual(file.kind, "PNG")
    }

    func testAPictureOverTheLimitIsRefused() throws {
        let url = folder.appendingPathComponent("big.png")
        try Data(repeating: 0x00, count: DroppedFile.maxImageBytes + 1).write(to: url)
        XCTAssertThrowsError(try DroppedFile.read(url)) { error in
            XCTAssertEqual(error as? DroppedFile.ReadError, .tooLarge("big.png", DroppedFile.maxImageBytes))
        }
    }

    func testAnUnsupportedPictureIsRefused() throws {
        let url = folder.appendingPathComponent("scan.heic")
        try Data([0x00, 0x01]).write(to: url)
        XCTAssertThrowsError(try DroppedFile.read(url)) { error in
            XCTAssertEqual(error as? DroppedFile.ReadError, .notText("scan.heic"))
        }
    }

    func testPicturesAreNotSentAsText() {
        let picture = DroppedFile(name: "shot.png", text: "", image: ChatImage(name: "shot.png", mimeType: "image/png", data: Data([1])))
        XCTAssertEqual(DroppedFile.context(for: [picture], limit: 1000), "")
    }

    func testContextNamesEachFileAndIsCutToTheLimit() {
        let files = [DroppedFile(name: "a.swift", text: "let a = 1"), DroppedFile(name: "b.swift", text: "let b = 2")]
        let context = DroppedFile.context(for: files, limit: 10_000)
        XCTAssertTrue(context.contains("File a.swift (attached):"))
        XCTAssertTrue(context.contains("let b = 2"))
        XCTAssertLessThanOrEqual(DroppedFile.context(for: files, limit: 20).count, 20)
    }
}

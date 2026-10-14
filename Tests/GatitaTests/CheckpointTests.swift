//
//  CheckpointTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// Checkpoints: the files a reply wrote or edited can be put back the way they were before it.
@MainActor
final class CheckpointTests: XCTestCase {
    private var root: URL!
    private var directory: URL!

    override func setUpWithError() throws {
        root = try makeProjectFixture(self)
        directory = temporaryFolder(self, name: "checkpoints")
    }

    private func read(_ path: String) -> String? {
        try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func write(_ path: String, _ text: String) throws {
        try text.write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8)
    }

    func testTheFileIsKeptAsItWasBeforeTheReplysFirstChange() throws {
        let recorder = CheckpointRecorder(replyID: UUID(), root: root, directory: directory)
        recorder.before("App/GatitaApp.swift")
        try write("App/GatitaApp.swift", "let app = 2\n")
        recorder.after("App/GatitaApp.swift")
        recorder.before("App/GatitaApp.swift")
        try write("App/GatitaApp.swift", "let app = 3\n")
        recorder.after("App/GatitaApp.swift")
        recorder.before("App/New.swift")
        try write("App/New.swift", "let new = 1\n")
        recorder.after("App/New.swift")

        let files = recorder.checkpoint.files
        XCTAssertEqual(files["App/GatitaApp.swift"]?.original, "let app = 1\n", "the first snapshot is kept")
        XCTAssertEqual(files["App/GatitaApp.swift"]?.latest, "let app = 3\n")
        XCTAssertEqual(files["App/New.swift"], Checkpoint.FileState(original: nil, latest: "let new = 1\n"),
                       "a file the reply made did not exist before")
        XCTAssertEqual(CheckpointStore.load(recorder.replyID, in: directory), recorder.checkpoint, "saved as it goes")
    }

    func testUndoPutsFilesBackAndRemovesNewOnes() throws {
        let recorder = CheckpointRecorder(replyID: UUID(), root: root, directory: directory)
        recorder.before("App/GatitaApp.swift")
        try write("App/GatitaApp.swift", "let app = 2\n")
        recorder.after("App/GatitaApp.swift")
        recorder.before("App/New.swift")
        try write("App/New.swift", "let new = 1\n")
        recorder.after("App/New.swift")

        let result = CheckpointStore.undo(recorder.checkpoint, force: false)
        XCTAssertEqual(result, CheckpointStore.UndoResult(restored: ["App/GatitaApp.swift", "App/New.swift"], conflicts: []))
        XCTAssertEqual(read("App/GatitaApp.swift"), "let app = 1\n")
        XCTAssertNil(read("App/New.swift"))
    }

    func testAFileChangedSinceIsNotOverwrittenUnlessYouSaySo() throws {
        let recorder = CheckpointRecorder(replyID: UUID(), root: root, directory: directory)
        recorder.before("App/GatitaApp.swift")
        try write("App/GatitaApp.swift", "let app = 2\n")
        recorder.after("App/GatitaApp.swift")
        try write("App/GatitaApp.swift", "let app = 99 // mine\n")

        XCTAssertEqual(CheckpointStore.undo(recorder.checkpoint, force: false).conflicts, ["App/GatitaApp.swift"])
        XCTAssertEqual(read("App/GatitaApp.swift"), "let app = 99 // mine\n", "nothing changed yet")
        XCTAssertEqual(CheckpointStore.undo(recorder.checkpoint, force: true).restored, ["App/GatitaApp.swift"])
        XCTAssertEqual(read("App/GatitaApp.swift"), "let app = 1\n")
    }

    func testANewReplyTakesOverTheChangesOfTheRepliesItReplaced() throws {
        let first = CheckpointRecorder(replyID: UUID(), root: root, directory: directory)
        first.before("App/GatitaApp.swift")
        try write("App/GatitaApp.swift", "let app = 2\n")
        first.after("App/GatitaApp.swift")
        let second = CheckpointRecorder(replyID: UUID(), root: root, directory: directory)
        second.before("App/GatitaApp.swift")
        try write("App/GatitaApp.swift", "let app = 3\n")
        second.after("App/GatitaApp.swift")
        second.before("App/New.swift")
        try write("App/New.swift", "let new = 1\n")
        second.after("App/New.swift")

        let next = CheckpointRecorder(replyID: UUID(), root: root, directory: directory,
                                      inheriting: [second.checkpoint, first.checkpoint])
        XCTAssertEqual(next.checkpoint.files["App/GatitaApp.swift"],
                       Checkpoint.FileState(original: "let app = 1\n", latest: "let app = 3\n"), "the oldest original, the newest text")
        XCTAssertNotNil(CheckpointStore.load(next.replyID, in: directory), "saved at once, even if the new reply changes nothing")

        next.before("App/GatitaApp.swift")
        try write("App/GatitaApp.swift", "let app = 4\n")
        next.after("App/GatitaApp.swift")
        XCTAssertEqual(CheckpointStore.undo(next.checkpoint, force: false).conflicts, [])
        XCTAssertEqual(read("App/GatitaApp.swift"), "let app = 1\n", "back to before the first replaced reply")
        XCTAssertNil(read("App/New.swift"))
    }

    func testOnlyChangesInTheSameProjectAreTakenOver() {
        let elsewhere = Checkpoint(replyID: UUID(), root: "/somewhere/else",
                                   files: ["a.txt": .init(original: "x", latest: "y")], savedAt: Date())
        let next = CheckpointRecorder(replyID: UUID(), root: root, directory: directory, inheriting: [elsewhere])
        XCTAssertTrue(next.checkpoint.files.isEmpty)
        XCTAssertNil(CheckpointStore.load(next.replyID, in: directory))
    }

    func testAPathOutsideTheProjectIsNeverTouched() throws {
        let outside = Checkpoint(replyID: UUID(), root: root.path,
                                 files: ["../escape.txt": .init(original: "x", latest: nil)], savedAt: Date())
        XCTAssertEqual(CheckpointStore.undo(outside, force: true).restored, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.deletingLastPathComponent().appendingPathComponent("escape.txt").path))
    }

    func testUndoNeverFollowsALinkOutOfTheProjectOrTouchesGit() throws {
        let outside = temporaryFolder(self, name: "outside").appendingPathComponent("secret.txt")
        try "keep me\n".write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("App/link.txt"), withDestinationURL: outside)
        let checkpoint = Checkpoint(replyID: UUID(), root: root.path,
                                    files: ["App/link.txt": .init(original: "changed", latest: nil),
                                            ".git/config": .init(original: "changed", latest: nil)], savedAt: Date())
        XCTAssertEqual(CheckpointStore.undo(checkpoint, force: true).restored, [])
        XCTAssertEqual(try String(contentsOf: outside, encoding: .utf8), "keep me\n")
        XCTAssertEqual(read(".git/config"), "secret")
    }

    func testOldCheckpointsAreCleanedUp() {
        let old = Checkpoint(replyID: UUID(), root: root.path, files: [:], savedAt: Date(timeIntervalSinceNow: -40 * 86_400))
        let new = Checkpoint(replyID: UUID(), root: root.path, files: [:], savedAt: Date())
        CheckpointStore.save(old, in: directory)
        CheckpointStore.save(new, in: directory)
        CheckpointStore.removeOld(in: directory, now: Date())
        XCTAssertEqual(CheckpointStore.replyIDs(in: directory), [new.replyID])
        CheckpointStore.remove(new.replyID, in: directory)
        XCTAssertEqual(CheckpointStore.replyIDs(in: directory), [])
    }
}

/// A reply's writes and edits are recorded as they happen (against the mock Gatita API).
final class CheckpointLoopTests: XCTestCase {
    private static var mock: Process?

    override class func setUp() {
        super.setUp()
        mock = try? MockGatita.start()
    }

    override class func tearDown() {
        mock?.terminate()
        mock?.waitUntilExit()
        mock = nil
        super.tearDown()
    }

    @MainActor
    func testAReplysChangesAreRecorded() async throws {
        let root = try makeProjectFixture(self)
        let recorder = CheckpointRecorder(replyID: UUID(), root: root, directory: temporaryFolder(self, name: "checkpoints"))
        let client = GatitaClient(apiKey: "test-key", baseURL: MockGatita.base,
                                  tools: ProjectTools(root: root, allowWrites: true), checkpoints: recorder)
        let answer = try await client.send(messages: [ChatMessage(role: "user", content: "WRITE-CHECK please")])
        XCTAssertEqual(answer, "mock: wrote")
        XCTAssertEqual(recorder.checkpoint.files["App/GatitaApp.swift"]?.original, "let app = 1\n")
        XCTAssertEqual(recorder.checkpoint.files["App/New.swift"], Checkpoint.FileState(original: nil, latest: "let new = 1\n"))
        XCTAssertEqual(CheckpointStore.undo(recorder.checkpoint, force: false).conflicts, [])
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("App/GatitaApp.swift"), encoding: .utf8), "let app = 1\n")
    }
}

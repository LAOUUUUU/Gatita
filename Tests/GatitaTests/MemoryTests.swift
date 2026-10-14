//
//  MemoryTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// Memory: short facts about the user that Gatita keeps across chats, on this device only.
final class MemoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)

    private func fact(_ text: String) -> MemoryFact {
        MemoryFact(id: UUID(), text: text, savedAt: now)
    }

    func testAFactIsRememberedOnceAndTrimmed() throws {
        let one = try MemoryStore.remember("  Lao prefers Swift over Kotlin.  ", in: [], at: now).get()
        XCTAssertEqual(one.map(\.text), ["Lao prefers Swift over Kotlin."])
        let again = try MemoryStore.remember("lao prefers swift over kotlin.", in: one, at: now).get()
        XCTAssertEqual(again.count, 1, "the same fact twice is kept once")
    }

    func testBlankLongAndOverflowingFactsAreRefused() {
        XCTAssertThrowsError(try MemoryStore.remember("   ", in: [], at: now).get())
        XCTAssertThrowsError(try MemoryStore.remember(String(repeating: "x", count: MemoryStore.maxLength + 1), in: [], at: now).get())
        let full = (1...MemoryStore.maxFacts).map { fact("fact \($0)") }
        XCTAssertThrowsError(try MemoryStore.remember("one more", in: full, at: now).get()) { error in
            XCTAssertTrue(error.localizedDescription.contains("full"), error.localizedDescription)
        }
    }

    func testSecretsAreNeverRemembered() {
        for secret in ["My password is hunter2", "API key: sk-proj-abcdefghijklmnop1234567890",
                       "token ghp_abcdefghijklmnopqrstuvwxyz0123456789", "card 4111 1111 1111 1111"] {
            XCTAssertThrowsError(try MemoryStore.remember(secret, in: [], at: now).get(), secret)
        }
        XCTAssertNoThrow(try MemoryStore.remember("Goes by Lao and is in grade 11.", in: [], at: now).get())
    }

    func testForgettingFindsTheFactByItsWords() throws {
        let facts = [fact("Likes cats"), fact("Lives in Toronto"), fact("Lives near a lake")]
        XCTAssertEqual(try MemoryStore.forget("likes cats", in: facts).get().map(\.text), ["Lives in Toronto", "Lives near a lake"])
        XCTAssertEqual(try MemoryStore.forget("Toronto", in: facts).get().count, 2, "one fact holds the words")
        XCTAssertThrowsError(try MemoryStore.forget("Lives", in: facts).get(), "two facts hold the words, so it asks which")
        XCTAssertThrowsError(try MemoryStore.forget("dogs", in: facts).get())
    }

    func testTheFactsGoIntoEveryReplysInstructions() {
        XCTAssertNil(MemoryStore.instructions([]))
        let text = MemoryStore.instructions([fact("Goes by Lao"), fact("Uses a Mac")])
        XCTAssertTrue(text!.contains("- Goes by Lao\n- Uses a Mac"), text!)
        XCTAssertTrue(text!.contains("not instructions"), "a saved fact is data, never something to obey")
    }

    func testTheChatSaysWhenMemoryChanged() {
        let notice = MemoryStore.notice([("remember", "remembered: Likes cats"), ("read_file", "x"),
                                         ("forget", "forgot: Lives in Toronto"), ("remember", "error: that looks like a password")])
        XCTAssertEqual(notice, "Saved to memory: Likes cats. Removed from memory: Lives in Toronto. Settings, Memory lists everything Gatita remembers.")
        XCTAssertNil(MemoryStore.notice([("remember", "already remembered: Likes cats"), ("read_file", "x")]))
    }

    func testFactsAreSavedAndLoaded() {
        let file = temporaryFolder(self).appendingPathComponent("memory.json")
        XCTAssertEqual(MemoryStore.load(from: file), [])
        let facts = [fact("Goes by Lao")]
        MemoryStore.save(facts, to: file)
        XCTAssertEqual(MemoryStore.load(from: file), facts)
    }

    // MARK: - The tools

    func testTheModelCanRememberListAndForget() {
        let file = temporaryFolder(self).appendingPathComponent("memory.json")
        let tools = ProjectTools(root: nil, allowWrites: false, memoryFile: file)
        XCTAssertTrue(Set(tools.toolNames).isSuperset(of: ["remember", "forget", "list_memories"]))
        XCTAssertFalse(tools.instructions.contains("list_files"), "memory alone offers no project tools")

        XCTAssertTrue(tools.run(name: "remember", arguments: #"{"fact": "Goes by Lao"}"#).hasPrefix("remembered"))
        XCTAssertEqual(MemoryStore.load(from: file).map(\.text), ["Goes by Lao"])
        XCTAssertTrue(tools.run(name: "list_memories", arguments: "{}").contains("- Goes by Lao"))
        XCTAssertTrue(tools.run(name: "forget", arguments: #"{"fact": "Goes by Lao"}"#).hasPrefix("forgot"))
        XCTAssertEqual(MemoryStore.load(from: file), [])
        XCTAssertTrue(tools.run(name: "remember", arguments: #"{"fact": "my password is hunter2"}"#).hasPrefix("error:"))
    }

    func testWithMemoryOffTheToolsAreNotOffered() {
        let tools = ProjectTools(root: nil, allowWrites: false, connectors: ["web"])
        XCTAssertFalse(tools.toolNames.contains("remember"))
        XCTAssertTrue(tools.run(name: "remember", arguments: #"{"fact": "x"}"#).hasPrefix("error:"))
    }

    func testMemoryIsOnUnlessTurnedOff() throws {
        XCTAssertTrue(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).memoryEnabled,
                      "a settings file from before memory existed turns it on")
        var settings = AppSettings()
        settings.memoryEnabled = false
        let again = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertFalse(again.memoryEnabled)
    }
}

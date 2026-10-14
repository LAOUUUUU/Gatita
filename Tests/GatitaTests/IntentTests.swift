//
//  IntentTests.swift
//  GatitaTests
//

import AppIntents
import XCTest
@testable import Gatita

/// "Ask Gatita" in Shortcuts and Siri.
final class IntentTests: XCTestCase {
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

    func testAQuestionNeedsWordsAKeyAndTheInternet() {
        XCTAssertThrowsError(try IntentAnswer.check(question: "  ", key: "k", online: true)) { error in
            XCTAssertEqual(error.localizedDescription, "Say or type a question for Gatita.")
        }
        XCTAssertThrowsError(try IntentAnswer.check(question: "Hi", key: " ", online: true)) { error in
            XCTAssertEqual(error.localizedDescription, "Add your Gatita API key in Gatita's Settings first.")
        }
        XCTAssertThrowsError(try IntentAnswer.check(question: "Hi", key: "k", online: false)) { error in
            XCTAssertEqual(error.localizedDescription, NoInternet.headline)
        }
        XCTAssertNoThrow(try IntentAnswer.check(question: "Hi", key: "k", online: true))
    }

    func testSiriSaysAShortPlainVersion() {
        XCTAssertEqual(IntentAnswer.spoken("## Answer\n\nIt is **42**.\n\n```swift\nlet x = 42\n```"), "Answer\nIt is 42.\nCode block skipped.")
        let long = String(repeating: "Words go on. ", count: 60)
        XCTAssertLessThanOrEqual(IntentAnswer.spoken(long).count, IntentAnswer.maxSpoken + 1)
        XCTAssertTrue(IntentAnswer.spoken(long).hasSuffix("…"))
    }

    func testTheQuestionIsAnsweredLikeAChat() async throws {
        let client = GatitaClient(apiKey: "test-key", baseURL: MockGatita.base)
        let asked = try await IntentAnswer.ask("Hello there", with: client)
        XCTAssertEqual(asked.answer, "mock: no tool instructions")
        XCTAssertTrue(asked.toolCalls.isEmpty)
    }

    func testTheShortcutIsListed() {
        XCTAssertFalse(GatitaShortcuts.appShortcuts.isEmpty)
        XCTAssertEqual(String(localized: AskGatitaIntent.title), "Ask Gatita")
    }
}

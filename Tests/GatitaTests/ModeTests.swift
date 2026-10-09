//
//  ModeTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// Chat and Code: only Code has project tools, GitHub needs Code and a project, and the choice is remembered.
final class ModeTests: XCTestCase {
    func testOnlyCodeUsesProjectTools() {
        XCTAssertFalse(GatitaMode.chat.usesProjectTools)
        XCTAssertTrue(GatitaMode.code.usesProjectTools)
    }

    func testGitHubIsOnlyForCodeWithAProject() {
        XCTAssertEqual(GatitaMode.chat.connectors(["github", "web"], hasProject: true), ["web"])
        XCTAssertEqual(GatitaMode.code.connectors(["github", "web"], hasProject: false), ["web"])
        XCTAssertEqual(GatitaMode.code.connectors(["github", "web"], hasProject: true), ["github", "web"])
    }

    func testAChatOnTheMacHasNoReportOrQuestionTools() {
        XCTAssertFalse(GatitaMode.chat.usesReportTools)
        XCTAssertTrue(GatitaMode.code.usesReportTools)
    }

    func testAChatWithAConnectorOffersOnlyThatConnector() {
        let tools = ProjectTools(root: nil, allowWrites: false, connectors: ["web"], allowsReports: false)
        XCTAssertFalse(tools.instructions.contains("list_reports"))
        XCTAssertFalse(tools.instructions.contains("ask_user"))
        XCTAssertTrue(tools.instructions.contains("web_"))
        XCTAssertEqual(tools.run(name: "list_reports", arguments: "{}"), "error: unknown tool list_reports")
    }

    func testOtherConnectorsWorkInBothModes() {
        XCTAssertEqual(GatitaMode.chat.connectors(["web", "calendar"], hasProject: false), ["web", "calendar"])
    }

    func testAChatKeepsTheModeItWasStartedIn() throws {
        var chat = Conversation(id: UUID(), updatedAt: Date(), messages: [ChatMessage(role: "user", content: "hi")])
        chat.mode = .chat
        let loaded = try JSONDecoder().decode(Conversation.self, from: try JSONEncoder().encode(chat))
        XCTAssertEqual(loaded.mode, .chat)

        let older = try JSONDecoder().decode(Conversation.self, from: try JSONEncoder().encode(
            Conversation(id: UUID(), updatedAt: Date(), messages: [])))
        XCTAssertNil(older.mode)
    }

    func testTheModeIsSavedAndOldSettingsDefaultToCode() throws {
        var settings = AppSettings()
        settings.mode = .chat
        let loaded = try JSONDecoder().decode(AppSettings.self, from: try JSONEncoder().encode(settings))
        XCTAssertEqual(loaded.mode, .chat)

        let older = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"model":"gatita-7.1-max"}"#.utf8))
        XCTAssertEqual(older.mode, .code)
    }
}

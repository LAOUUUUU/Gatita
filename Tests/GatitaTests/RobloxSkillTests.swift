//
//  RobloxSkillTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// The built-in Roblox skill, picked with "/roblox".
final class RobloxSkillTests: XCTestCase {
    private var text: String { Skills.instructions(for: "roblox") ?? "" }

    func testTheRobloxSkillIsOfferedAndFoundByName() {
        XCTAssertNotNil(Skills.instructions(for: "roblox"))
        XCTAssertEqual(Skills.all.first { $0.id == "roblox" }?.name, "Roblox")
        XCTAssertEqual(Composer.skills(matching: "roblox", in: Skills.all).map(\.id), ["roblox"])
    }

    func testItTeachesHowScriptFilesAreNamedAndWhatSyncLeavesOut() {
        for phrase in ["Name.luau", "Name.server.luau", "Name.client.luau", "Name.local.luau", "init.server.luau",
                       "*.project.json", "attributes or tags"] {
            XCTAssertTrue(text.contains(phrase), "the skill should mention \(phrase)")
        }
    }

    func testItTeachesTheStudioToolWorkflow() {
        for phrase in ["list_roblox_studios", "studio_id", "search_game_tree", "script_read", "multi_edit",
                       "execute_luau", "get_console_output"] {
            XCTAssertTrue(text.contains(phrase), "the skill should mention \(phrase)")
        }
    }

    func testItDoesNotLetTheModelClaimLuauRanOrWorked() {
        XCTAssertTrue(text.contains("cannot run Luau yourself"), text)
        XCTAssertTrue(text.contains("until the console output shows it"), text)
    }
}

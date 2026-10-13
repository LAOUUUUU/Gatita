//
//  SkillsTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// The built-in skills: preset instructions picked with "/".
final class SkillsTests: XCTestCase {
    func testEverySkillHasItsOwnIdAndInstructions() {
        let ids = Skills.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertFalse(ids.contains(Skills.none))
        for skill in Skills.all {
            XCTAssertFalse(skill.name.isEmpty, skill.id)
            XCTAssertGreaterThan(skill.instructions.count, 80, skill.id)
        }
    }

    func testTheNewSkillsAreOffered() {
        for id in ["debug", "refactor", "commit", "docs", "security-check", "deps", "research", "summarize", "tutor", "writing"] {
            XCTAssertNotNil(Skills.instructions(for: id), id)
        }
    }

    func testSkillsThatUseAConnectorSayToCheckItIsOn() {
        XCTAssertTrue(Skills.instructions(for: "deps")?.contains("package_info") == true)
        XCTAssertTrue(Skills.instructions(for: "deps")?.contains("Packages connector") == true)
        XCTAssertTrue(Skills.instructions(for: "research")?.contains("wikipedia_search") == true)
    }

    func testTypingASkillNameFindsIt() {
        XCTAssertEqual(Composer.skills(matching: "bug", in: Skills.all).map(\.id), ["debug"])
        XCTAssertEqual(Composer.skills(matching: "commit", in: Skills.all).map(\.id), ["commit"])
    }
}

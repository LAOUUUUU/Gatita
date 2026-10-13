//
//  CustomInstructionsTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// Your own instructions, read before every reply, with the skill's instructions after them.
final class CustomInstructionsTests: XCTestCase {
    func testYourInstructionsComeBeforeTheSkillWithABlankLineBetween() {
        XCTAssertEqual(CustomInstructions.systemText(custom: "Answer in short sentences.", skill: "Use bullet points."),
                       "Answer in short sentences.\n\nUse bullet points.")
    }

    func testTheSkillAloneIsStillSent() {
        XCTAssertEqual(CustomInstructions.systemText(custom: "", skill: "Use bullet points."), "Use bullet points.")
    }

    func testBlankInstructionsAddNothing() {
        XCTAssertNil(CustomInstructions.systemText(custom: "   \n", skill: nil))
    }

    func testLongInstructionsAreCapped() {
        let text = CustomInstructions.systemText(custom: String(repeating: "a", count: 9_000), skill: nil)
        XCTAssertEqual(text?.count, CustomInstructions.maxCharacters)
    }
}

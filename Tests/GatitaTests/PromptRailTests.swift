//
//  PromptRailTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// The prompt rail highlights the prompt on screen. At the bottom, it highlights the last prompt.
final class PromptRailTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID()

    private var positions: [UUID: CGFloat] {
        [a: 0, b: 500, c: 1000]
    }

    func testAtTheBottomTheLastPromptIsCurrent() {
        XCTAssertEqual(PromptRail.current(order: [a, b, c], positions: positions, offset: 900, atBottom: true), c)
    }

    func testTheLastPromptThatReachedTheTopIsCurrent() {
        XCTAssertEqual(PromptRail.current(order: [a, b, c], positions: positions, offset: 600, atBottom: false), b)
    }

    func testBeforeAnyPromptReachesTheTopTheFirstIsCurrent() {
        XCTAssertEqual(PromptRail.current(order: [a, b, c], positions: [a: 100, b: 500, c: 1000], offset: 0, atBottom: false), a)
    }

    func testNoPromptsMeansNothingIsCurrent() {
        XCTAssertNil(PromptRail.current(order: [], positions: [:], offset: 0, atBottom: true))
    }
}

//
//  ProjectBarTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

#if os(macOS)
/// The project bar shortens long folder and branch names, so each chip is only as wide as its text.
final class ProjectBarTests: XCTestCase {
    func testAShortNameIsKeptWhole() {
        XCTAssertEqual(ProjectBar.shortened("Gatita", to: 24), "Gatita")
    }

    func testALongNameIsShortenedInTheMiddle() {
        let name = "feature/very-long-branch-name-for-testing"
        let short = ProjectBar.shortened(name, to: 20)
        XCTAssertEqual(short.count, 20, short)
        XCTAssertTrue(short.hasPrefix("feature/"), short)
        XCTAssertTrue(short.hasSuffix("testing"), short)
        XCTAssertTrue(short.contains("…"), short)
    }
}
#endif

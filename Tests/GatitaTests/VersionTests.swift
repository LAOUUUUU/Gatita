//
//  VersionTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// The version is MAJOR.MINOR.PATCH, and the newest changelog entry names the same version.
final class VersionTests: XCTestCase {
    func testVersionHasThreeNumbers() {
        let parts = AppVersion.number.split(separator: ".")
        XCTAssertEqual(parts.count, 3, AppVersion.number)
        XCTAssertTrue(parts.allSatisfy { Int($0) != nil }, AppVersion.number)
    }

    func testNewestChangelogEntryMatchesTheAppVersion() throws {
        let text = try String(contentsOf: RepoPaths.root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
        let newest = text.components(separatedBy: "\n").first { $0.hasPrefix("## ") }
        XCTAssertEqual(newest, "## \(AppVersion.number) \(AppVersion.channel)")
    }
}

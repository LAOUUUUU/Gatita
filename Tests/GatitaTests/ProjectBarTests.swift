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

    @MainActor
    func testStudioCountsAsConnectedOnlyForAConnectedRobloxServer() {
        // Any server with "roblox" in its name will do, since the user picks the name.
        XCTAssertTrue(ProjectBar.studioIsConnected(["roblox_studio": .connected(tools: 26)]))
        XCTAssertTrue(ProjectBar.studioIsConnected(["my-roblox": .connected(tools: 3), "github": .off]))
        XCTAssertFalse(ProjectBar.studioIsConnected(["roblox_studio": .connecting]))
        XCTAssertFalse(ProjectBar.studioIsConnected(["roblox_studio": .failed("Studio is not running")]))
        XCTAssertFalse(ProjectBar.studioIsConnected(["roblox_studio": .off]))
        XCTAssertFalse(ProjectBar.studioIsConnected(["github": .connected(tools: 5)]))
        XCTAssertFalse(ProjectBar.studioIsConnected([:]))
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

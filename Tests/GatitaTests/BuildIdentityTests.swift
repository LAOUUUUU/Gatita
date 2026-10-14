//
//  BuildIdentityTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

#if os(macOS)
/// Gatita asks macOS for Input Monitoring and Screen Recording again when the build is not the one that asked last
/// time, since an ad-hoc build is a new identity to macOS after every rebuild.
final class BuildIdentityTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "gatita-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testItAsksTheFirstTime() {
        XCTAssertTrue(BuildIdentity.shouldAsk(lastAskedFor: nil, current: "build A"))
        XCTAssertTrue(BuildIdentity.shouldAsk(lastAskedFor: nil, current: nil))
    }

    func testItDoesNotAskAgainForTheSameIdentity() {
        XCTAssertFalse(BuildIdentity.shouldAsk(lastAskedFor: "build A", current: "build A"))
    }

    func testItAsksAgainWhenTheIdentityChanged() {
        XCTAssertTrue(BuildIdentity.shouldAsk(lastAskedFor: "build A", current: "build B"))
    }

    func testWhenTheIdentityCannotBeReadItAsksOnlyOnce() {
        XCTAssertFalse(BuildIdentity.shouldAsk(lastAskedFor: "build A", current: nil))
        XCTAssertFalse(BuildIdentity.shouldAsk(lastAskedFor: "unknown", current: nil))
    }

    func testAskOnceRemembersWhichBuildAsked() {
        let defaults = freshDefaults()
        XCTAssertTrue(BuildIdentity.askOnce("inputMonitoring", defaults: defaults, current: "build A"))
        XCTAssertFalse(BuildIdentity.askOnce("inputMonitoring", defaults: defaults, current: "build A"))
        XCTAssertTrue(BuildIdentity.askOnce("inputMonitoring", defaults: defaults, current: "build B"), "a rebuild is a new identity")
        XCTAssertTrue(BuildIdentity.askOnce("screenRecording", defaults: defaults, current: "build B"), "each permission has its own memory")
    }

    func testAskOnceWithAnUnreadableIdentityAsksOnce() {
        let defaults = freshDefaults()
        XCTAssertTrue(BuildIdentity.askOnce("inputMonitoring", defaults: defaults, current: nil))
        XCTAssertFalse(BuildIdentity.askOnce("inputMonitoring", defaults: defaults, current: nil))
    }

    func testTheRunningAppHasAnIdentity() {
        // The test host is Gatita itself, which is at least ad-hoc signed, so macOS has a requirement to compare.
        XCTAssertNotNil(BuildIdentity.current())
    }
}
#endif

//
//  DoubleTapTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// Pressing ⌘ twice opens the quick panel. Only two quick taps of ⌘ on its own count, so shortcuts such as ⌘C
/// never open it.
final class DoubleTapTests: XCTestCase {
    /// Taps ⌘ down at `start` and up `hold` seconds later. True when that tap completed a double tap.
    private func tap(_ detector: inout DoubleTapDetector, at start: TimeInterval, hold: TimeInterval = 0.1) -> Bool {
        _ = detector.flagsChanged(commandDown: true, otherModifiersDown: false, at: start)
        return detector.flagsChanged(commandDown: false, otherModifiersDown: false, at: start + hold)
    }

    func testTwoQuickTapsOpenThePanel() {
        var detector = DoubleTapDetector()
        XCTAssertFalse(tap(&detector, at: 0))
        XCTAssertTrue(tap(&detector, at: 0.25))
    }

    func testTwoSlowTapsDoNot() {
        var detector = DoubleTapDetector()
        XCTAssertFalse(tap(&detector, at: 0))
        XCTAssertFalse(tap(&detector, at: 0.9))
    }

    func testAShortcutBetweenTheTapsDoesNotCount() {
        var detector = DoubleTapDetector()
        XCTAssertFalse(tap(&detector, at: 0))
        _ = detector.flagsChanged(commandDown: true, otherModifiersDown: false, at: 0.2)
        detector.keyDown()   // ⌘C
        XCTAssertFalse(detector.flagsChanged(commandDown: false, otherModifiersDown: false, at: 0.3))
    }

    func testHoldingCommandIsNotATap() {
        var detector = DoubleTapDetector()
        XCTAssertFalse(tap(&detector, at: 0))
        XCTAssertFalse(tap(&detector, at: 0.2, hold: 0.8))
    }

    func testCommandWithAnotherModifierIsNotATap() {
        var detector = DoubleTapDetector()
        XCTAssertFalse(tap(&detector, at: 0))
        _ = detector.flagsChanged(commandDown: true, otherModifiersDown: true, at: 0.2)   // ⌘⇧
        XCTAssertFalse(detector.flagsChanged(commandDown: false, otherModifiersDown: false, at: 0.3))
    }

    func testAThirdTapStartsOver() {
        var detector = DoubleTapDetector()
        XCTAssertFalse(tap(&detector, at: 0))
        XCTAssertTrue(tap(&detector, at: 0.25))
        XCTAssertFalse(tap(&detector, at: 0.5), "the third tap does not open it again at once")
        XCTAssertTrue(tap(&detector, at: 0.75))
    }

    func testAKeyTypedBeforeTheFirstTapDoesNotSpoilIt() {
        var detector = DoubleTapDetector()
        detector.keyDown()
        XCTAssertFalse(tap(&detector, at: 1))
        XCTAssertTrue(tap(&detector, at: 1.2))
    }

    func testTheSettingIsOnByDefaultAndSaved() throws {
        XCTAssertTrue(AppSettings().doubleCommandOpensPanel)
        let data = try JSONEncoder().encode(AppSettings(doubleCommandOpensPanel: false))
        XCTAssertFalse(try JSONDecoder().decode(AppSettings.self, from: data).doubleCommandOpensPanel)
        XCTAssertTrue(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).doubleCommandOpensPanel,
                      "a settings file from before the switch existed keeps it on")
    }
}

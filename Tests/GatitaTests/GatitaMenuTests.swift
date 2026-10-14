//
//  GatitaMenuTests.swift
//  GatitaTests
//

import CoreGraphics
import XCTest
@testable import Gatita

/// Where Gatita's own dropdown menus open: under their button when there is room, above it when not, and never
/// past the window's edges.
final class GatitaMenuTests: XCTestCase {
    private let window = CGSize(width: 1000, height: 700)
    private let card = CGSize(width: 240, height: 150)

    func testAMenuOpensUnderItsButtonAlignedToItsTrailingEdge() {
        let button = CGRect(x: 900, y: 10, width: 30, height: 30)
        let origin = GatitaMenuLayout.origin(for: card, under: button, in: window, alignTrailing: true)
        XCTAssertEqual(origin, CGPoint(x: 690, y: 46))
    }

    func testAMenuNearTheBottomOpensAboveItsButton() {
        let button = CGRect(x: 100, y: 640, width: 26, height: 26)
        let origin = GatitaMenuLayout.origin(for: card, under: button, in: window, alignTrailing: false)
        XCTAssertEqual(origin, CGPoint(x: 100, y: 640 - 6 - 150))
    }

    func testAMenuNeverLeavesTheWindow() {
        let button = CGRect(x: 2, y: 10, width: 30, height: 30)
        XCTAssertEqual(GatitaMenuLayout.origin(for: card, under: button, in: window, alignTrailing: true).x, 8)
        let right = CGRect(x: 980, y: 10, width: 30, height: 30)
        XCTAssertEqual(GatitaMenuLayout.origin(for: card, under: right, in: window, alignTrailing: false).x, 1000 - 240 - 8)
    }

    func testATallMenuInASmallWindowStaysOnScreen() {
        let tall = CGSize(width: 240, height: 680)
        let button = CGRect(x: 100, y: 300, width: 30, height: 30)
        XCTAssertEqual(GatitaMenuLayout.origin(for: tall, under: button, in: window, alignTrailing: false).y, 8)
    }

    func testEveryTranscriptViewSaysWhatItShows() {
        for view in TranscriptView.allCases {
            XCTAssertFalse(view.summary.isEmpty, view.title)
        }
    }

    @MainActor
    func testEscapeIsClaimedWhileAnyDialogOrMenuIsOpen() {
        let claims = EscapeClaims()
        let dialog = UUID()
        let menu = UUID()
        XCTAssertFalse(claims.isClaimed)
        claims.set(dialog, claimed: true)
        claims.set(menu, claimed: true)
        claims.set(dialog, claimed: false)
        XCTAssertTrue(claims.isClaimed, "the menu is still open")
        claims.set(menu, claimed: false)
        XCTAssertFalse(claims.isClaimed)
        claims.set(menu, claimed: false)
        XCTAssertFalse(claims.isClaimed, "closing twice is harmless")
    }

    func testTheQuickPanelSaysWhyAReplyHasNoAnswer() {
        XCTAssertEqual(QuickAnswer.problem(answer: "", error: nil, safetyStopped: true, stopped: false),
                       "Gatita stopped this reply for safety.")
        XCTAssertEqual(QuickAnswer.problem(answer: "Half an", error: nil, safetyStopped: true, stopped: false),
                       "Gatita stopped this reply for safety.")
        XCTAssertEqual(QuickAnswer.problem(answer: "", error: nil, safetyStopped: false, stopped: false),
                       "Gatita ended the reply without writing an answer.")
        XCTAssertEqual(QuickAnswer.problem(answer: "", error: nil, safetyStopped: false, stopped: true), "Stopped.")
        XCTAssertNil(QuickAnswer.problem(answer: "Half", error: nil, safetyStopped: false, stopped: true))
        XCTAssertNil(QuickAnswer.problem(answer: "Done.", error: nil, safetyStopped: false, stopped: false))
        XCTAssertEqual(QuickAnswer.problem(answer: "", error: "No internet.", safetyStopped: false, stopped: false), "No internet.")
    }
}

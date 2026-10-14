//
//  ServicesTests.swift
//  GatitaTests
//

import AppKit
import XCTest
@testable import Gatita

/// "Ask Gatita" in the Services menu of any Mac app: the selected text opens the quick panel.
final class ServicesTests: XCTestCase {
    func testTheAppDeclaresTheService() throws {
        let services = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "NSServices") as? [[String: Any]])
        let ask = try XCTUnwrap(services.first { $0["NSMessage"] as? String == "askGatita" })
        XCTAssertEqual(ask["NSPortName"] as? String, "Gatita")
        XCTAssertEqual((ask["NSMenuItem"] as? [String: String])?["default"], "Ask Gatita")
        XCTAssertEqual(ask["NSSendTypes"] as? [String], ["NSStringPboardType"])
    }

    @MainActor
    func testTheServiceHandsOverTheSelectedText() {
        var received: String?
        let provider = GatitaServices { received = $0 }
        XCTAssertEqual(NSStringFromSelector(#selector(GatitaServices.askGatita(_:userData:error:))), "askGatita:userData:error:",
                       "the name macOS calls, from NSMessage in Info.plist")
        let board = NSPasteboard(name: NSPasteboard.Name("GatitaServicesTest-\(UUID().uuidString)"))
        board.clearContents()
        board.setString("  Explain this  ", forType: .string)
        var error: NSString = ""
        provider.askGatita(board, userData: nil, error: &error)
        XCTAssertEqual(received, "Explain this")

        board.clearContents()
        received = nil
        provider.askGatita(board, userData: nil, error: &error)
        XCTAssertNil(received, "nothing selected opens nothing")
        XCTAssertFalse((error as String).isEmpty)
    }

    func testTheSelectedTextGoesWithTheQuestion() {
        XCTAssertEqual(QuickPanelContext.text(selected: "x = 1", clipboard: nil), "The text the user selected:\n```\nx = 1\n```")
        let both = QuickPanelContext.text(selected: "a", clipboard: "b")
        XCTAssertTrue(both.contains("selected:\n```\na\n```") && both.contains("clipboard:\n```\nb\n```"), both)
        XCTAssertEqual(QuickPanelContext.text(selected: nil, clipboard: nil), "")
        XCTAssertEqual(QuickPanelContext.question(typed: "  ", hasSelection: true), "Explain this text.")
        XCTAssertEqual(QuickPanelContext.question(typed: "Translate it", hasSelection: true), "Translate it")
    }
}

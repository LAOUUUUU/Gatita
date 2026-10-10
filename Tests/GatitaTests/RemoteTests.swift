//
//  RemoteTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// Chats sent between paired devices: the pairing rule, the message on the wire, and the saved setting.
final class RemoteTests: XCTestCase {
    private let open = Date().addingTimeInterval(300)

    func testADeviceWithTheRightCodeIsAcceptedWhilePairingIsOpen() {
        XCTAssertTrue(HostSession.accepts(Data("1234".utf8), pairingCode: "1234", pairingOpenUntil: open))
    }

    func testAWrongOrMissingCodeIsRefused() {
        XCTAssertFalse(HostSession.accepts(Data("9999".utf8), pairingCode: "1234", pairingOpenUntil: open))
        XCTAssertFalse(HostSession.accepts(nil, pairingCode: "1234", pairingOpenUntil: open))
    }

    func testSpacesAroundTheCodeDoNotStopPairing() {
        XCTAssertTrue(HostSession.accepts(Data("1234".utf8), pairingCode: " 1234 ", pairingOpenUntil: open))
    }

    func testNothingPairsWhilePairingIsClosedOrExpired() {
        XCTAssertFalse(HostSession.accepts(Data("1234".utf8), pairingCode: "1234", pairingOpenUntil: nil))
        XCTAssertFalse(HostSession.accepts(Data("1234".utf8), pairingCode: "1234", pairingOpenUntil: Date().addingTimeInterval(-1)))
    }

    func testWithNoCodeSetNoDeviceGetsIn() {
        XCTAssertFalse(HostSession.accepts(Data("".utf8), pairingCode: "", pairingOpenUntil: open))
        XCTAssertFalse(HostSession.accepts(Data("1234".utf8), pairingCode: "", pairingOpenUntil: open))
    }

    func testAChatSurvivesTheWire() throws {
        let data = try JSONEncoder().encode(RemoteMessage.prompt(text: "hi", clientName: "iPad"))
        guard case .prompt(let text, let name)? = try? JSONDecoder().decode(RemoteMessage.self, from: data) else {
            return XCTFail("the chat did not decode as a prompt")
        }
        XCTAssertEqual(text, "hi")
        XCTAssertEqual(name, "iPad")
    }

    func testTheConnectionLineSaysWhatIsHappening() {
        XCTAssertEqual(RemoteStatus.line(connectedName: "Lao's MacBook"),
                       "Connected to Lao's MacBook. It's up. What would you like to do?")
        XCTAssertEqual(RemoteStatus.line(connectedName: nil),
                       "Not connected to your Mac. Connect to it in Settings, then Pairing.")
    }

    func testTheMacSaysWhenADeviceIsConnected() {
        XCTAssertNil(RemoteStatus.hostLine(names: []))
        XCTAssertEqual(RemoteStatus.hostLine(names: ["iPad"]),
                       "iPad is connected. It's up. What would you like to do?")
    }
}

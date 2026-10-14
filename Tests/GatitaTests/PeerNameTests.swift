//
//  PeerNameTests.swift
//  GatitaTests
//

import MultipeerConnectivity
import XCTest
@testable import Gatita

/// The name another device sees when pairing. MultipeerConnectivity throws on a name that is empty or longer than
/// 63 bytes of UTF-8. A Mac's network host name can be that long (GitHub's test Macs have one), and the exception
/// left SwiftUI's observation tracking broken, so the app crashed later.
final class PeerNameTests: XCTestCase {
    func testAShortNameIsKept() {
        XCTAssertEqual(PeerName.safe("Lao's MacBook Pro", fallback: "Gatita"), "Lao's MacBook Pro")
    }

    func testAMissingOrBlankNameUsesTheFallback() {
        XCTAssertEqual(PeerName.safe(nil, fallback: "Gatita Host"), "Gatita Host")
        XCTAssertEqual(PeerName.safe("  \n", fallback: "Gatita Host"), "Gatita Host")
    }

    func testALongNameIsCutToSixtyThreeBytesBetweenCharacters() {
        let host = "sat12-bq123-" + String(repeating: "a1b2c3d4", count: 10) + ".local"
        let cut = PeerName.safe(host, fallback: "Gatita")
        XCTAssertEqual(cut.utf8.count, 63)
        XCTAssertTrue(host.hasPrefix(cut))
        _ = MCPeerID(displayName: cut)

        let cats = String(repeating: "🐱", count: 20)
        XCTAssertEqual(PeerName.safe(cats, fallback: "Gatita"), String(repeating: "🐱", count: 15), "4 bytes each, never split")
    }
}

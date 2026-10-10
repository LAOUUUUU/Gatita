//
//  PairingCodeTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// The code the Mac makes each time it opens pairing. The phone types it in.
final class PairingCodeTests: XCTestCase {
    func testACodeIsSixDigits() {
        let code = PairingCode.make()
        XCTAssertEqual(code.count, 6, code)
        XCTAssertTrue(code.allSatisfy { $0.isNumber }, code)
    }

    func testLeadingZerosStayInTheCode() {
        // Over many codes, some start with 0. Each one must still have six digits.
        for _ in 0..<2_000 {
            XCTAssertEqual(PairingCode.make().count, 6)
        }
    }
}

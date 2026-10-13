//
//  NoInternetTests.swift
//  GatitaTests
//

import Network
import XCTest
@testable import Gatita

/// With no internet, the chat says so plainly instead of showing a raw network error.
final class NoInternetTests: XCTestCase {
    func testOfflineErrorsAreRecognised() {
        XCTAssertTrue(NoInternet.matches(URLError(.notConnectedToInternet), online: true))
        XCTAssertTrue(NoInternet.matches(URLError(.dataNotAllowed), online: true))
        XCTAssertTrue(NoInternet.matches(URLError(.internationalRoamingOff), online: true))
    }

    func testOtherNetworkErrorsCountOnlyWhenTheDeviceIsOffline() {
        XCTAssertFalse(NoInternet.matches(URLError(.timedOut), online: true))
        XCTAssertTrue(NoInternet.matches(URLError(.timedOut), online: false))
        XCTAssertTrue(NoInternet.matches(URLError(.cannotFindHost), online: false))
    }

    func testErrorsThatAreNotAboutTheNetworkNeverCount() {
        XCTAssertFalse(NoInternet.matches(GatitaError.http(status: 500, body: ""), online: false))
        XCTAssertFalse(NoInternet.matches(ToolError("bad path"), online: false))
        XCTAssertFalse(NoInternet.matches(URLError(.cancelled), online: false))
    }

    func testOnlyASatisfiedOrWakeablePathCountsAsOnline() {
        XCTAssertTrue(Connectivity.isOnline(.satisfied))
        XCTAssertTrue(Connectivity.isOnline(.requiresConnection), "a path that wakes up on demand, such as a VPN, is not offline")
        XCTAssertFalse(Connectivity.isOnline(.unsatisfied))
    }

    func testTheMessageSaysErrorNoInternetAccess() {
        XCTAssertEqual(NoInternet.headline, "Error: No internet access.")
        XCTAssertFalse(NoInternet.detail.isEmpty)
    }

    func testAConnectorThatCannotReachTheInternetSaysSo() {
        let text = NoInternet.toolError(service: "Weather")
        XCTAssertTrue(text.hasPrefix("error: no internet access"), text)
        XCTAssertTrue(text.contains("Weather"), text)
    }
}

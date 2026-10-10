//
//  WebCurlTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// The raw web request: status, main headers, and the body as text. Same address rules as the page reader.
final class WebCurlTests: XCTestCase {
    func testShowsTheStatusHeadersAndBody() throws {
        let output = try WebCurl.render(status: 200, url: "https://api.example.com/v1/items",
                                        headers: ["Content-Type": "application/json", "Content-Length": "15"],
                                        body: Data(#"{"ok": true}"#.utf8))
        XCTAssertTrue(output.hasPrefix("HTTP 200 https://api.example.com/v1/items"), output)
        XCTAssertTrue(output.contains("content-type: application/json"), output)
        XCTAssertTrue(output.contains("content-length: 15"), output)
        XCTAssertTrue(output.hasSuffix(#"{"ok": true}"#), output)
    }

    func testAnErrorStatusStillShowsItsBody() throws {
        let output = try WebCurl.render(status: 404, url: "https://example.com/missing",
                                        headers: ["content-type": "text/plain"],
                                        body: Data("not found".utf8))
        XCTAssertTrue(output.hasPrefix("HTTP 404"), output)
        XCTAssertTrue(output.hasSuffix("not found"), output)
    }

    func testBinaryBodiesAreNotShownAsText() {
        XCTAssertThrowsError(try WebCurl.render(status: 200, url: "https://example.com/logo.png",
                                                headers: ["Content-Type": "image/png"],
                                                body: Data([0x89, 0x50, 0x4E, 0x47])))
    }

    func testTheBodyIsCapped() throws {
        let long = String(repeating: "a", count: 30_000)
        let output = try WebCurl.render(status: 200, url: "https://example.com/big",
                                        headers: ["content-type": "text/plain"], body: Data(long.utf8))
        XCTAssertLessThanOrEqual(output.count, 20_200)
        XCTAssertTrue(output.contains("[cut at 20,000 characters]"), "the cut is marked")
    }

    func testOnlyPublicHttpsAddressesAreRequested() async {
        do {
            _ = try await WebCurl.fetch("https://localhost/x")
            XCTFail("a local address was requested")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("public https"), error.localizedDescription)
        }
    }

    func testTheWebConnectorOffersTheRawRequest() {
        XCTAssertEqual(Connectors.connector(for: "web_curl")?.id, "web")
        XCTAssertTrue(Connectors.toolHelp(for: Connectors.connector(named: "web")!).contains { $0.contains("web_curl") })
    }
}

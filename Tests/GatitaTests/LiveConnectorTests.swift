//
//  LiveConnectorTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// Runs each public connector against the real service. Skipped unless GATITA_LIVE_TESTS=1, so the normal
/// test run never needs the internet. With xcodebuild, pass it as TEST_RUNNER_GATITA_LIVE_TESTS=1.
final class LiveConnectorTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["GATITA_LIVE_TESTS"] == "1", "live connector tests are off")
    }

    private func run(_ tool: String, _ arguments: [String: String], expect: String) async throws {
        let text = try await Connectors.run(tool, arguments: arguments, root: nil)
        print("----- \(tool)\n\(text.prefix(600))")
        XCTAssertTrue(text.contains(expect), "\(tool): \(text.prefix(400))")
    }

    func testWeather() async throws {
        try await run("weather", ["place": "Toronto, Canada", "days": "2"], expect: "Weather for Toronto, Ontario, Canada")
    }

    func testWikipedia() async throws {
        try await run("wikipedia_search", ["query": "Swift programming language"], expect: "Swift (programming language)")
        try await run("wikipedia_page", ["title": "Swift (programming language)"], expect: "Source: https://en.wikipedia.org/wiki/")
    }

    func testDictionary() async throws {
        try await run("define", ["word": "serendipity"], expect: "noun")
    }

    func testCurrency() async throws {
        try await run("exchange_rates", ["from": "USD", "to": "CAD", "amount": "10"], expect: "10 USD = ")
    }

    func testPackages() async throws {
        try await run("package_info", ["registry": "npm", "name": "react"], expect: "Latest version: ")
        try await run("package_info", ["registry": "pypi", "name": "requests"], expect: "Latest version: ")
        try await run("package_info", ["registry": "crates", "name": "serde"], expect: "Latest version: ")
        try await run("package_info", ["registry": "go", "name": "github.com/BurntSushi/toml"], expect: "Latest version: v")
    }

    func testStackOverflow() async throws {
        try await run("stackoverflow_search", ["query": "swift async let cancel"], expect: "(question ")
        try await run("stackoverflow_answers", ["id": "26567419"], expect: "## Answer 1")
    }

    func testPublicRepos() async throws {
        try await run("repo_info", ["repo": "LAOUUUUU/Gatita"], expect: "Newest release: v")
        try await run("repo_readme", ["repo": "LAOUUUUU/Gatita"], expect: "README of LAOUUUUU/Gatita")
    }
}

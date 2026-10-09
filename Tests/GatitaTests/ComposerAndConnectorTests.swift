//
//  ComposerAndConnectorTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// The composer's "/", "@", and "!" triggers, and the connectors behind "!". Connectors start off, and web reads stay public.
final class ComposerAndConnectorTests: XCTestCase {
    // MARK: - Composer

    func testSlashAtTheStartOpensSkills() {
        XCTAssertEqual(Composer.activeToken(in: "/rev"), ComposerToken(trigger: .skill, query: "rev"))
        XCTAssertNil(Composer.activeToken(in: "hello /rev"))
    }

    func testAtSignAnywhereOpensFiles() {
        XCTAssertEqual(Composer.activeToken(in: "look at @Git"), ComposerToken(trigger: .file, query: "Git"))
    }

    func testBangAnywhereOpensPlugins() {
        XCTAssertEqual(Composer.activeToken(in: "use !test"), ComposerToken(trigger: .plugin, query: "test"))
    }

    func testAFinishedWordClosesTheMenuAndAChoiceReplacesTheToken() {
        XCTAssertNil(Composer.activeToken(in: "look at @Git "))
        XCTAssertEqual(Composer.replacingActiveToken(in: "look at @Gat", with: "@App/GatitaApp.swift"),
                       "look at @App/GatitaApp.swift ")
    }

    func testSkillsAndFilesFilter() {
        XCTAssertEqual(Composer.skills(matching: "rev", in: Skills.all).map(\.id), ["review", "web"])
        XCTAssertEqual(Composer.files(matching: "gatita", in: ["App/GatitaApp.swift", "Shared/Other.swift"]), ["App/GatitaApp.swift"])
    }

    func testMentionsAreReadFromTheMessage() {
        XCTAssertEqual(Composer.mentions(in: "fix @App/GatitaApp.swift and !test-tools please"), ["App/GatitaApp.swift"])
        XCTAssertEqual(Composer.pluginMentions(in: "fix @App/GatitaApp.swift and !test-tools please"), ["test-tools"])
    }

    // MARK: - GitHub

    func testGitHubRepoIsReadFromHTTPSAndSSHRemotes() {
        XCTAssertEqual(GitHubConnector.repo(fromRemote: "https://github.com/LAOUUUUU/Gatita.git"), "LAOUUUUU/Gatita")
        XCTAssertEqual(GitHubConnector.repo(fromRemote: "git@github.com:owner/repo.git"), "owner/repo")
        XCTAssertNil(GitHubConnector.repo(fromRemote: "https://gitlab.com/x/y.git"))
    }

    func testGitHubListsFormatAsLines() {
        XCTAssertEqual(
            GitHubFormat.pullRequests(json: #"[{"number": 3, "title": "Fix buttons", "author": {"login": "lao"}, "headRefName": "gatita/fix", "url": "https://github.com/o/r/pull/3", "isDraft": false}]"#),
            "#3 Fix buttons (lao, gatita/fix) https://github.com/o/r/pull/3")
        XCTAssertEqual(GitHubFormat.pullRequests(json: "[]"), "(none)")
        XCTAssertEqual(
            GitHubFormat.issues(json: #"[{"number": 7, "title": "Crash on launch", "state": "OPEN", "url": "https://github.com/o/r/issues/7", "author": {"login": "lao"}}]"#),
            "#7 Crash on launch (OPEN, lao) https://github.com/o/r/issues/7")
    }

    func testGitHubNumbersAndStatesAreChecked() {
        XCTAssertEqual(GitHubConnector.number("12"), 12)
        XCTAssertNil(GitHubConnector.number("3; rm -rf"))
        XCTAssertEqual(GitHubConnector.state("open"), "open")
        XCTAssertNil(GitHubConnector.state("delete"))
    }

    // MARK: - Web pages

    func testWebPagesMustBeHTTPS() {
        XCTAssertNotNil(WebFetch.validate("https://developer.apple.com/xcode"))
        XCTAssertNil(WebFetch.validate("http://example.com"))
    }

    func testWebPagesCannotPointAtThisMacOrItsNetwork() {
        XCTAssertNil(WebFetch.validate("https://localhost/x"))
        XCTAssertNil(WebFetch.validate("https://192.168.1.5/"))
        XCTAssertNil(WebFetch.validate("https://127.0.0.1/"))
        XCTAssertNil(WebFetch.validate("https://172.20.0.1/"))
    }

    func testHTMLBecomesReadableText() {
        XCTAssertEqual(WebFetch.plainText(from: "<h1>Title</h1><script>var x=1</script><p>Hi &amp; bye</p>"), "Title Hi & bye")
    }

    func testAConnectorStaysOffUntilItIsTurnedOn() async throws {
        let root = try makeProjectFixture(self)
        let disabled = await ProjectTools(root: root, allowWrites: false)
            .execute(name: "web_fetch", arguments: #"{"url": "https://example.com"}"#)
        XCTAssertTrue(disabled.hasPrefix("error:") && disabled.contains("turned off"), disabled)
    }
}

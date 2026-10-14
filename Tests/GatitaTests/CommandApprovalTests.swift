//
//  CommandApprovalTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// Asking before a command runs: Allow once, Always allow (saved per project), or Deny.
final class CommandApprovalTests: XCTestCase {
    func testTheRuleIsTheAllowedCommandThatMatched() {
        XCTAssertEqual(CommandApproval.rule(for: "swift test --filter Foo", allowed: CommandPolicy.builtIn), "swift test")
        XCTAssertEqual(CommandApproval.rule(for: "python3 -m pytest tests", allowed: CommandPolicy.builtIn), "python3 -m pytest")
        XCTAssertNil(CommandApproval.rule(for: "rm -rf build", allowed: CommandPolicy.builtIn), "a command that is not allowed has no rule")
    }

    func testARuleCoversItsCommandWithAnyArgumentsAndNothingElse() {
        XCTAssertTrue(CommandApproval.covers(["swift test"], "swift test --filter X"))
        XCTAssertTrue(CommandApproval.covers(["swift test"], "swift test"))
        XCTAssertFalse(CommandApproval.covers(["swift test"], "swift build"))
        XCTAssertFalse(CommandApproval.covers(["swift test"], "swift testing"), "a rule ends at a whole word")
        XCTAssertFalse(CommandApproval.covers([], "swift test"))
    }

    func testAlwaysAllowIsKeptPerProject() {
        var rules = CommandApproval.adding("swift test", project: "/a", to: [:])
        rules = CommandApproval.adding("swift test", project: "/a", to: rules)
        rules = CommandApproval.adding("npm test", project: "/b", to: rules)
        XCTAssertEqual(rules["/a"], ["swift test"], "a rule is saved once")
        XCTAssertEqual(CommandApproval.rules(for: "/b", in: rules), ["npm test"])
        XCTAssertEqual(CommandApproval.rules(for: "/c", in: rules), [])
    }

    private func decide(_ command: String, rule: String, ask: Bool = true, rules: [String] = [], trusted: Bool = false,
                        unattended: Bool = false) -> CommandApproval.Decision? {
        CommandApproval.decision(for: .init(command: command, rule: rule), askBeforeCommands: ask, rules: rules,
                                 trustedMCP: trusted, unattended: unattended)
    }

    func testWhenToAskBeforeACommand() {
        XCTAssertNil(decide("swift test", rule: "swift test"), "ask")
        XCTAssertEqual(decide("swift test", rule: "swift test", ask: false), .allowOnce, "asking is off")
        XCTAssertEqual(decide("swift test -v", rule: "swift test", rules: ["swift test"]), .allowOnce, "always allowed")
    }

    func testAnUntrustedMCPToolIsAlwaysAskedAbout() {
        XCTAssertNil(decide("mcp__gh__create_issue {}", rule: "mcp__gh__create_issue", ask: false),
                     "turning off asking before commands does not cover MCP tools")
        XCTAssertEqual(decide("mcp__gh__create_issue {}", rule: "mcp__gh__create_issue", trusted: true), .allowOnce)
        XCTAssertEqual(decide("mcp__gh__create_issue {}", rule: "mcp__gh__create_issue", rules: ["mcp__gh__create_issue"]), .allowOnce)
    }

    func testAScheduledRunNeverWaitsForAnAnswer() {
        XCTAssertEqual(decide("swift test", rule: "swift test", unattended: true), .deny, "nobody is there to answer")
        XCTAssertEqual(decide("swift test", rule: "swift test", rules: ["swift test"], unattended: true), .allowOnce)
        XCTAssertEqual(decide("mcp__gh__x {}", rule: "mcp__gh__x", ask: false, unattended: true), .deny)
    }

    func testAskingIsOnAndNoRulesAreSavedAtFirst() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertTrue(settings.askBeforeCommands)
        XCTAssertEqual(settings.commandRules, [:])
        var changed = AppSettings()
        changed.askBeforeCommands = false
        changed.commandRules = ["/a": ["swift test"]]
        let again = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(changed))
        XCTAssertFalse(again.askBeforeCommands)
        XCTAssertEqual(again.commandRules, ["/a": ["swift test"]])
    }
}

/// The client waits for the answer before a command runs (against the mock Gatita API).
final class CommandApprovalLoopTests: XCTestCase {
    private static var mock: Process?

    override class func setUp() {
        super.setUp()
        mock = try? MockGatita.start()
    }

    override class func tearDown() {
        mock?.terminate()
        mock?.waitUntilExit()
        mock = nil
        super.tearDown()
    }

    @MainActor
    final class Asked {
        var rules: [String] = []
    }

    @MainActor
    func testADeniedCommandDoesNotRunAndTheModelIsTold() async throws {
        let tools = ProjectTools(root: try makeProjectFixture(self), allowWrites: false, allowCommands: true)
        let asked = Asked()
        let client = GatitaClient(apiKey: "test-key", baseURL: MockGatita.base, tools: tools,
                                  approveCommand: { request in
                                      asked.rules.append(request.rule)
                                      return .deny
                                  })
        let answer = try await client.send(messages: [ChatMessage(role: "user", content: "RUN-CHECK please")])
        XCTAssertEqual(answer, "mock: denied")
        XCTAssertEqual(asked.rules, ["swift --version"])
    }

    @MainActor
    func testAnAllowedCommandRuns() async throws {
        let tools = ProjectTools(root: try makeProjectFixture(self), allowWrites: false, allowCommands: true)
        let client = GatitaClient(apiKey: "test-key", baseURL: MockGatita.base, tools: tools,
                                  approveCommand: { _ in .allowOnce })
        let answer = try await client.send(messages: [ChatMessage(role: "user", content: "RUN-CHECK please")])
        XCTAssertEqual(answer, "mock: ran")
    }
}

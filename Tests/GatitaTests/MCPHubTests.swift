//
//  MCPHubTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// Starting a local MCP server, listing its tools, and calling them (against Tests/MockServer/mock_mcp_server.py).
@MainActor
final class MCPHubTests: XCTestCase {
    private func mock(_ name: String = "Mock") -> MCPServerConfig {
        MCPServerConfig(name: name, command: "/usr/bin/python3", args: [RepoPaths.mockMCPServer.path], env: [:],
                        url: nil, disabled: false, trusted: false)
    }

    func testALocalServerStartsAndItsToolsAreCalled() async {
        let hub = MCPHub()
        await hub.connect(mock())
        XCTAssertEqual(hub.status["mock"], .connected(tools: 3))
        XCTAssertTrue(hub.toolHelp.contains(#"- mcp__mock__echo: {"tool": "mcp__mock__echo", "text": "<string: What to echo>"} Echoes text back."#),
                      hub.toolHelp.joined(separator: "\n"))

        let echoed = await hub.call("mcp__mock__echo", block: #"{"tool": "mcp__mock__echo", "text": "hi"}"#)
        XCTAssertEqual(echoed, "echo: hi")
        let broken = await hub.call("mcp__mock__broken", block: #"{"tool": "mcp__mock__broken"}"#)
        XCTAssertEqual(broken, "error: it broke")
        let unknown = await hub.call("mcp__nope__x", block: "{}")
        XCTAssertTrue(unknown.hasPrefix("error:"), unknown)

        await hub.disconnect("Mock")
        XCTAssertEqual(hub.status["mock"], .off)
        XCTAssertTrue(hub.toolHelp.isEmpty)
    }

    func testAServerThatCannotStartSaysWhy() async {
        let hub = MCPHub()
        var bad = mock("Bad")
        bad.command = "no-such-command-for-gatita"
        await hub.connect(bad)
        guard case .failed(let reason) = hub.status["bad"] else {
            return XCTFail("expected a failure, got \(String(describing: hub.status["bad"]))")
        }
        XCTAssertTrue(reason.contains("no-such-command-for-gatita"), reason)
    }

    func testACallThatNeverAnswersTimesOut() async {
        let hub = MCPHub()
        hub.callTimeout = .seconds(1)
        await hub.connect(mock())
        let started = Date()
        let result = await hub.call("mcp__mock__hang", block: #"{"tool": "mcp__mock__hang"}"#)
        XCTAssertTrue(result.hasPrefix("error:") && result.contains("did not answer"), result)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
        await hub.disconnect("Mock")
    }

    func testStoppingTheReplyEndsAWaitingCall() async {
        let hub = MCPHub()
        await hub.connect(mock())
        let call = Task { await hub.call("mcp__mock__hang", block: #"{"tool": "mcp__mock__hang"}"#) }
        try? await Task.sleep(for: .milliseconds(300))
        let started = Date()
        call.cancel()
        let result = await call.value
        XCTAssertTrue(result.hasPrefix("error:"), result)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2, "Stop ends it at once")
        await hub.disconnect("Mock")
    }

    func testAServerThatNeverAnswersFailsInsteadOfHanging() async {
        let hub = MCPHub()
        hub.startTimeout = .seconds(1)
        var silent = mock("Silent")
        silent.env = ["MOCK_MCP_MODE": "silent"]
        let started = Date()
        await hub.connect(silent)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
        guard case .failed(let reason) = hub.status["silent"] else {
            return XCTFail("expected a failure, got \(String(describing: hub.status["silent"]))")
        }
        XCTAssertTrue(reason.contains("did not answer"), reason)
    }

    func testAServerRemovedWhileStartingStaysRemoved() async {
        let hub = MCPHub()
        var slow = mock("Slow")
        slow.env = ["MOCK_MCP_MODE": "slow"]
        let starting = Task { await hub.connect(slow) }
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(hub.status["slow"], .connecting)
        await hub.disconnect("Slow")
        await starting.value
        XCTAssertEqual(hub.status["slow"], .off, "the start that finished late does not bring it back")
        XCTAssertTrue(hub.toolHelp.isEmpty)
    }

    func testAServerCanBeTrusted() async {
        let hub = MCPHub()
        var trusted = mock()
        trusted.trusted = true
        await hub.connect(trusted)
        XCTAssertTrue(hub.isTrusted("mcp__mock__echo"))
        XCTAssertFalse(hub.isTrusted("mcp__other__echo"))
        XCTAssertEqual(hub.toolHelp(onlyTrusted: true).count, 3, "places that can't ask get only trusted tools")

        trusted.trusted = false
        hub.update(trusted)
        XCTAssertFalse(hub.isTrusted("mcp__mock__echo"), "trust changes without a restart")
        XCTAssertEqual(hub.toolHelp(onlyTrusted: true), [])
        XCTAssertEqual(hub.toolHelp.count, 3)
        await hub.disconnect("Mock")
    }
}

/// The chat sends MCP tool calls to their server, after asking (against the mock Gatita API and mock MCP server).
final class MCPLoopTests: XCTestCase {
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
    private func client(_ hub: MCPHub, answer: CommandApproval.Decision, asked: Asked) -> GatitaClient {
        GatitaClient(apiKey: "test-key", baseURL: MockGatita.base,
                     tools: ProjectTools(root: nil, allowWrites: false, extraToolHelp: hub.toolHelp),
                     approveCommand: { request in
                         asked.rules.append(request.rule)
                         return answer
                     },
                     mcp: { name, block in await hub.call(name, block: block) })
    }

    @MainActor
    func testAnMCPCallGoesToItsServerAfterAsking() async throws {
        let hub = MCPHub()
        await hub.connect(MCPServerConfig(name: "Mock", command: "/usr/bin/python3", args: [RepoPaths.mockMCPServer.path],
                                          env: [:], url: nil, disabled: false, trusted: false))
        let asked = Asked()
        let answer = try await client(hub, answer: .allowOnce, asked: asked)
            .send(messages: [ChatMessage(role: "user", content: "MCP-CHECK please")])
        XCTAssertEqual(answer, "mock: echo: hi")
        XCTAssertEqual(asked.rules, ["mcp__mock__echo"])

        let denied = try await client(hub, answer: .deny, asked: asked)
            .send(messages: [ChatMessage(role: "user", content: "MCP-CHECK please")])
        XCTAssertTrue(denied.hasPrefix("mock: error: the user denied"), denied)
        await hub.disconnect("Mock")
    }
}

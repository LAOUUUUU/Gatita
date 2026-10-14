//
//  MCPConfigTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// MCP servers: the mcp.json file (Claude Desktop's shape), tool names, and what the model is told.
final class MCPConfigTests: XCTestCase {
    func testClaudeDesktopsShapeIsRead() throws {
        let json = """
            {"mcpServers": {
              "github": {"command": "npx", "args": ["-y", "@modelcontextprotocol/server-github"], "env": {"GITHUB_TOKEN": "x"}},
              "linear": {"url": "https://mcp.linear.app/mcp"},
              "off": {"command": "uvx", "disabled": true, "trusted": true}
            }}
            """
        let servers = try MCPConfig.parse(Data(json.utf8))
        XCTAssertEqual(servers.map(\.name), ["github", "linear", "off"], "in name order")
        XCTAssertEqual(servers[0].command, "npx")
        XCTAssertEqual(servers[0].args, ["-y", "@modelcontextprotocol/server-github"])
        XCTAssertEqual(servers[0].env, ["GITHUB_TOKEN": "x"])
        XCTAssertFalse(servers[0].isRemote)
        XCTAssertEqual(servers[1].url, "https://mcp.linear.app/mcp")
        XCTAssertTrue(servers[1].isRemote)
        XCTAssertTrue(servers[2].disabled)
        XCTAssertTrue(servers[2].trusted)
        XCTAssertEqual(try MCPConfig.parse(Data("{}".utf8)), [])
    }

    func testTheFileSavesAndLoadsInTheSameShape() throws {
        let file = temporaryFolder(self).appendingPathComponent("mcp.json")
        XCTAssertEqual(MCPConfig.load(from: file), [])
        let servers = [MCPServerConfig(name: "files", command: "npx", args: ["-y", "x"], env: [:], url: nil, disabled: false, trusted: false)]
        MCPConfig.save(servers, to: file)
        XCTAssertEqual(MCPConfig.load(from: file), servers)
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        XCTAssertNotNil((raw["mcpServers"] as? [String: Any])?["files"], "other apps can read it")
    }

    func testImportOffersOnlyServersGatitaDoesNotHave() {
        func server(_ name: String) -> MCPServerConfig {
            MCPServerConfig(name: name, command: "npx", args: [], env: [:], url: nil, disabled: false, trusted: false)
        }
        let found = [server("github"), server("Linear"), server("notion")]
        XCTAssertEqual(MCPConfig.importable(found, existing: [server("GitHub")]).map(\.name), ["Linear", "notion"],
                       "GitHub and github would share their tools' names")
        XCTAssertEqual(MCPConfig.importable([], existing: []), [])
    }

    func testEachServerNeedsItsOwnName() {
        let servers = [MCPServerConfig(name: "GitHub", command: "npx", args: [], env: [:], url: nil, disabled: false, trusted: false)]
        XCTAssertEqual(MCPConfig.nameProblem("  ", among: servers, editing: nil), "Give the server a name.")
        XCTAssertEqual(MCPConfig.nameProblem("github", among: servers, editing: nil),
                       "There is already a server called GitHub. Pick another name.", "GitHub and github share their tools' names")
        XCTAssertNil(MCPConfig.nameProblem("GitHub", among: servers, editing: "GitHub"), "keeping its own name")
        XCTAssertNil(MCPConfig.nameProblem("Linear", among: servers, editing: nil))
    }

    func testToolNamesNameTheirServer() {
        XCTAssertEqual(MCPConfig.toolName(server: "GitHub Tools", tool: "create_issue"), "mcp__github_tools__create_issue")
        XCTAssertEqual(MCPConfig.split("mcp__github_tools__create_issue")?.server, "github_tools")
        XCTAssertEqual(MCPConfig.split("mcp__github_tools__create_issue")?.tool, "create_issue")
        XCTAssertEqual(MCPConfig.split("mcp__a__b__c")?.tool, "b__c", "a tool name may hold two underscores itself")
        XCTAssertNil(MCPConfig.split("read_file"))
        XCTAssertEqual(MCPConfig.serverKey("GitHub Tools"), "github_tools")
    }

    func testTheModelIsToldEachToolsArguments() {
        let line = MCPConfig.help(server: "github", tool: "create_issue", description: "Creates an issue.\nMore detail.",
                                  parameters: [MCPToolParameter(name: "title", type: "string", description: "The title", required: true),
                                               MCPToolParameter(name: "labels", type: "array", description: nil, required: false)])
        XCTAssertEqual(line, #"- mcp__github__create_issue: {"tool": "mcp__github__create_issue", "title": "<string: The title>", "labels": "<array, optional>"} Creates an issue."#)
    }

    func testArgumentsKeepTheirTypes() throws {
        let args = try XCTUnwrap(MCPConfig.arguments(in: #"{"tool": "mcp__a__b", "title": "Hi", "count": 3, "draft": true, "labels": ["x"]}"#))
        XCTAssertEqual(args["title"] as? String, "Hi")
        XCTAssertEqual(args["count"] as? Int, 3)
        XCTAssertEqual(args["draft"] as? Bool, true)
        XCTAssertEqual(args["labels"] as? [String], ["x"])
        XCTAssertNil(args["tool"], "the tool's own name is not an argument")
        XCTAssertNotNil(MCPConfig.arguments(in: "{\"tool\": \"mcp__a__b\", \"text\": \"line one\nline two\"}"), "a raw line break is repaired")
    }

    func testMCPToolsJoinTheToolList() {
        let help = [MCPConfig.help(server: "files", tool: "get-File2", description: "Reads a file.", parameters: [])]
        let tools = ProjectTools(root: nil, allowWrites: false, extraToolHelp: help)
        XCTAssertTrue(tools.instructions.contains(help[0]))
        XCTAssertTrue(tools.toolNames.contains("mcp__files__get-File2"), "names may hold capitals, digits, and hyphens")
        XCTAssertFalse(tools.instructions.contains("list_files"))
    }

    func testArgumentsAndEnvironmentAreTypedAsText() {
        XCTAssertEqual(MCPConfig.splitArguments(#"-y @modelcontextprotocol/server-filesystem "/Users/me/My Files" --read-only"#),
                       ["-y", "@modelcontextprotocol/server-filesystem", "/Users/me/My Files", "--read-only"])
        XCTAssertEqual(MCPConfig.splitArguments("  "), [])
        XCTAssertEqual(MCPConfig.joinArguments(["-y", "/Users/me/My Files"]), #"-y "/Users/me/My Files""#)
        XCTAssertEqual(MCPConfig.environment(from: "GITHUB_TOKEN=abc\n\n  DEBUG = 1 \nnot a pair"), ["GITHUB_TOKEN": "abc", "DEBUG": "1"])
        XCTAssertEqual(MCPConfig.environmentText(["B": "2", "A": "1"]), "A=1\nB=2")
    }

    func testALocalServerGetsOnlyTheBasicsAndItsOwnEnvironment() {
        let base = ["HOME": "/Users/me", "USER": "me", "PATH": "/usr/bin", "GATITA_API_KEY": "secret",
                    "AWS_SECRET_ACCESS_KEY": "x", "LANG": "en_US.UTF-8", "TMPDIR": "/tmp/me"]
        let environment = MCPProcess.environment(base: base, path: "/opt/homebrew/bin:/usr/bin", server: ["GITHUB_TOKEN": "t"])
        XCTAssertEqual(environment, ["HOME": "/Users/me", "USER": "me", "PATH": "/opt/homebrew/bin:/usr/bin",
                                     "LANG": "en_US.UTF-8", "TMPDIR": "/tmp/me", "GITHUB_TOKEN": "t"])
        XCTAssertNil(environment["GATITA_API_KEY"], "Gatita's own key never reaches a server")
    }

    func testThePathIsReadFromBetweenItsMarkers() {
        let output = "Welcome to zsh!\n" + MCPProcess.pathStart + "/opt/homebrew/bin:/usr/bin" + MCPProcess.pathEnd + "\nbye"
        XCTAssertEqual(MCPProcess.path(fromShellOutput: output), "/opt/homebrew/bin:/usr/bin")
        XCTAssertNil(MCPProcess.path(fromShellOutput: "no markers here"))
    }
}

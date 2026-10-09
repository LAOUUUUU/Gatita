//
//  CommandAndPluginTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// Commands run only from the allowed list, inside the macOS sandbox. Plugins add skills and commands. The shop installs them.
final class CommandAndPluginTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = try makeProjectFixture(self)
    }

    // MARK: - Commands

    func testArgvSplitsAPlainCommandAndRefusesShellSyntax() {
        XCTAssertEqual(CommandPolicy.argv("swift --version"), ["swift", "--version"])
        XCTAssertNil(CommandPolicy.argv("swift test; rm -rf /"))
        XCTAssertNil(CommandPolicy.argv("swift test | tee x"))
        XCTAssertNil(CommandPolicy.argv("echo \"x\""))
    }

    func testOnlyAllowedCommandsPass() {
        XCTAssertNil(CommandPolicy.allowed("rm -rf .", CommandPolicy.builtIn))
        XCTAssertEqual(CommandPolicy.allowed("swift test --filter Foo", CommandPolicy.builtIn),
                       ["swift", "test", "--filter", "Foo"])
    }

    func testSandboxDeniesNetworkAndWritesOutsideTheProject() {
        let profile = CommandPolicy.sandboxProfile(projectRoot: "/tmp/project")
        XCTAssertTrue(profile.contains("(deny network*)"))
        XCTAssertTrue(profile.contains("(deny file-write*)"))
        XCTAssertTrue(profile.contains("/tmp/project"))
    }

    func testRunCommandIsRefusedWhenCommandsAreOff() {
        let off = ProjectTools(root: root, allowWrites: false)
        XCTAssertTrue(off.run(name: "run_command", arguments: #"{"command": "swift --version"}"#).hasPrefix("error:"))
    }

    func testRunCommandRefusesCommandsNotOnTheList() {
        let commands = ProjectTools(root: root, allowWrites: false, allowCommands: true)
        XCTAssertTrue(commands.run(name: "run_command", arguments: #"{"command": "rm -rf ."}"#).hasPrefix("error:"))
    }

    func testRunCommandRunsAnAllowedCommandInTheSandbox() {
        let commands = ProjectTools(root: root, allowWrites: false, allowCommands: true)
        let output = commands.run(name: "run_command", arguments: #"{"command": "swift --version"}"#)
        XCTAssertTrue(output.contains("Swift version"), String(output.prefix(160)))
    }

    // MARK: - Plugins

    func testPluginSkillAndCommandLoadAndBrokenPluginsAreSkipped() throws {
        let pluginDir = temporaryFolder(self, name: "gatita-plugins")
        try FileManager.default.createDirectory(at: pluginDir.appendingPathComponent("demo"), withIntermediateDirectories: true)
        try #"{"name": "demo", "description": "test", "skills": [{"id": "lint", "name": "Lint", "instructions": "Run the linter."}], "commands": ["npm run lint"]}"#
            .write(to: pluginDir.appendingPathComponent("demo/plugin.json"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: pluginDir.appendingPathComponent("broken"), withIntermediateDirectories: true)
        try "{ nope".write(to: pluginDir.appendingPathComponent("broken/plugin.json"), atomically: true, encoding: .utf8)

        let loaded = Plugins.load(from: pluginDir)
        XCTAssertEqual(loaded.skills.map(\.id), ["plugin:demo:lint"])
        XCTAssertTrue(loaded.commands.contains(["npm", "run", "lint"]))
        XCTAssertEqual(loaded.names, ["demo"])
    }

    func testExamplePluginsLoadAndTheirCommandsPassThePolicy() {
        let shipped = Plugins.load(from: RepoPaths.plugins)
        XCTAssertTrue(["test-tools", "github", "web-design"].allSatisfy { shipped.names.contains($0) }, "\(shipped.names)")
        XCTAssertTrue(shipped.commands.contains(["git", "log", "--oneline"]))
        XCTAssertTrue(shipped.commands.allSatisfy {
            CommandPolicy.allowed($0.joined(separator: " "), CommandPolicy.builtIn + shipped.commands) != nil
        })
    }

    func testPluginCommandRunsInTheSandbox() {
        let shipped = Plugins.load(from: RepoPaths.plugins)
        let tools = ProjectTools(root: root, allowWrites: false, allowCommands: true,
                                 commands: CommandPolicy.builtIn + shipped.commands)
        XCTAssertTrue(tools.run(name: "run_command", arguments: #"{"command": "uname -a"}"#).contains("Darwin"))
    }

    func testGitRunsInTheSandbox() {
        let version = try? CommandRunner.run(["git", "--version"], in: root)
        XCTAssertTrue(version?.contains("git version") == true)
    }

    // MARK: - Shop

    func testShopHasThreeCategoriesAndValidItems() throws {
        let plugins = Shop.items.filter { $0.kind == .plugin }
        let skills = Shop.items.filter { $0.kind == .skill }
        let connectors = Shop.items.filter { $0.kind == .connector }
        XCTAssertFalse(plugins.isEmpty)
        XCTAssertFalse(skills.isEmpty)
        XCTAssertFalse(connectors.isEmpty)
        XCTAssertTrue((plugins + skills).allSatisfy { Shop.manifest(of: $0) != nil })
        XCTAssertTrue(plugins.allSatisfy { !(Shop.manifest(of: $0)?.commands ?? []).isEmpty })
        XCTAssertTrue(skills.allSatisfy { Shop.manifest(of: $0)?.skills?.count == 1 })
        XCTAssertTrue((plugins + skills).allSatisfy {
            Shop.manifest(of: $0)?.commands?.allSatisfy { CommandPolicy.argv($0) != nil } ?? true
        })
        XCTAssertTrue(Shop.items.allSatisfy { !Shop.permissions(of: $0).isEmpty })
        XCTAssertEqual(Set(Shop.items.map(\.id)).count, Shop.items.count)
        XCTAssertTrue(connectors.allSatisfy { $0.connectorID != nil })
    }

    func testInstallingAShopPluginWritesAFolderThatLoadsAndRemovingDeletesIt() throws {
        let shopDir = temporaryFolder(self, name: "gatita-shop")
        let plugin = Shop.items.first { $0.kind == .plugin }!
        try Shop.install(plugin, into: shopDir)
        XCTAssertTrue(Shop.isInstalled(plugin, in: shopDir))
        XCTAssertTrue(Plugins.load(from: shopDir).names.contains(Shop.manifest(of: plugin)?.name ?? "?"))
        try Shop.remove(plugin, from: shopDir)
        XCTAssertFalse(Shop.isInstalled(plugin, in: shopDir))
    }

    func testInstalledShopSkillLoadsAsOneSkill() throws {
        let shopDir = temporaryFolder(self, name: "gatita-shop")
        let skill = Shop.items.first { $0.kind == .skill }!
        try Shop.install(skill, into: shopDir)
        XCTAssertEqual(Plugins.load(from: shopDir).skills.count, 1)
        try Shop.remove(skill, from: shopDir)
    }
}

//
//  RobloxProjectTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// A folder is recognized as a Roblox project from its file names alone, so the project bar can say so.
final class RobloxProjectTests: XCTestCase {
    /// A new folder holding an empty file at each relative path.
    private func folder(with paths: [String]) throws -> URL {
        let root = temporaryFolder(self, name: "gatita-roblox")
        for path in paths {
            let file = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "".write(to: file, atomically: true, encoding: .utf8)
        }
        return root
    }

    func testARojoProjectFileMakesARojoProject() throws {
        let root = try folder(with: ["default.project.json", "README.md"])
        XCTAssertEqual(RobloxProject.detect(in: root), RobloxProject(kind: .rojo, evidence: "default.project.json"))
    }

    func testAnyNamedRojoProjectFileCounts() throws {
        // Rojo projects are "*.project.json" files, and a folder can hold several, such as place.project.json.
        let root = try folder(with: ["place.project.json"])
        XCTAssertEqual(RobloxProject.detect(in: root), RobloxProject(kind: .rojo, evidence: "place.project.json"))
    }

    func testScriptFilesNamedForTheirTypeMakeARobloxProject() throws {
        // The type sits before the extension: Studio's Script Sync writes .server/.client/.local/.legacy/.plugin, and
        // Rojo projects often still use .lua.
        for name in ["Main.server.luau", "Hud.client.luau", "Door.local.luau", "Old.legacy.luau", "Tool.plugin.luau",
                     "Boot.server.lua", "SHOUT.SERVER.LUAU"] {
            let root = try folder(with: [name, "README.md"])
            XCTAssertEqual(RobloxProject.detect(in: root), RobloxProject(kind: .scriptFiles, evidence: name), name)
        }
    }

    func testScriptsInSubfoldersCount() throws {
        let root = try folder(with: ["README.md", "src/server/Main.server.luau", "src/shared/Util.luau"])
        XCTAssertEqual(RobloxProject.detect(in: root),
                       RobloxProject(kind: .scriptFiles, evidence: "src/server/Main.server.luau"))
    }

    func testAProjectFileInASubfolderCounts() throws {
        // A repository can keep the game in a folder of its own.
        let root = try folder(with: ["README.md", "docs/guide.md", "game/default.project.json"])
        XCTAssertEqual(RobloxProject.detect(in: root), RobloxProject(kind: .rojo, evidence: "game/default.project.json"))
    }

    func testARojoProjectBeatsScriptFilesEvenWhenTheScriptsAreNearer() throws {
        let root = try folder(with: ["Main.server.luau", "game/default.project.json"])
        XCTAssertEqual(RobloxProject.detect(in: root), RobloxProject(kind: .rojo, evidence: "game/default.project.json"))
    }

    func testHiddenAndVendorFoldersAreNotSearched() throws {
        let root = try folder(with: [".git/hooks/Hook.server.luau", ".hidden/default.project.json",
                                     "node_modules/pkg/default.project.json", "node_modules/pkg/Main.server.luau"])
        XCTAssertNil(RobloxProject.detect(in: root))
    }

    func testOnlyAFewFoldersDeepAreSearched() throws {
        XCTAssertNotNil(RobloxProject.detect(in: try folder(with: ["a/b/c/Deep.server.luau"])), "three folders down is found")
        XCTAssertNil(RobloxProject.detect(in: try folder(with: ["a/b/c/d/Deep.server.luau"])), "four folders down is not")
    }

    func testAHugeFolderIsOnlySearchedUpToALimit() throws {
        // The bar looks at the project folder each time it changes, so a folder with thousands of entries must not
        // keep it busy. Names sort before the script, so the limit is reached first.
        let names = (0..<2_100).map { String(format: "file-%04d.txt", $0) }
        let root = try folder(with: names + ["zzz.server.luau"])
        XCTAssertNil(RobloxProject.detect(in: root))
    }

    func testTheChipExplainsWhatWasFoundAndHowEditsReachStudio() {
        let rojo = RobloxProject(kind: .rojo, evidence: "default.project.json").summary(studioConnected: false)
        XCTAssertTrue(rojo.contains("Rojo project (default.project.json)"), rojo)
        XCTAssertTrue(rojo.contains("while Rojo is serving"), "edits reach Studio only while Rojo serves the project: \(rojo)")

        let scripts = RobloxProject(kind: .scriptFiles, evidence: "src/Main.server.luau").summary(studioConnected: false)
        XCTAssertTrue(scripts.contains("script files (src/Main.server.luau)"), scripts)
        XCTAssertTrue(scripts.contains("Script Sync"), "edits reach Studio only while it syncs the folder: \(scripts)")

        for text in [rojo, scripts] {
            XCTAssertTrue(text.contains("/roblox"), "it points to the skill: \(text)")
            XCTAssertFalse(text.contains("Studio tools"), text)
        }
    }

    func testTheChipSaysWhenStudioToolsAreConnected() {
        let project = RobloxProject(kind: .rojo, evidence: "default.project.json")
        XCTAssertTrue(project.summary(studioConnected: true).contains("Studio tools are connected"))
        XCTAssertFalse(project.summary(studioConnected: false).contains("Studio tools are connected"))
    }

    func testAScriptTypeWordAloneIsNotEnough() throws {
        // "server.luau" has no name before the type, and ".server.luau" is a hidden file.
        for name in ["server.luau", "Main.server.txt", "Main.server", "notes.client.md"] {
            XCTAssertNil(RobloxProject.detect(in: try folder(with: [name])), name)
        }
    }

    func testOrdinaryFoldersAreNotRobloxProjects() throws {
        XCTAssertNil(RobloxProject.detect(in: try folder(with: ["README.md", "main.luau", "src/utils.luau", "project.json"])),
                     "plain Luau and a file called project.json are not Roblox")
        XCTAssertNil(RobloxProject.detect(in: try folder(with: [])))
        XCTAssertNil(RobloxProject.detect(in: URL(fileURLWithPath: "/no/such/folder-for-gatita")))
    }
}

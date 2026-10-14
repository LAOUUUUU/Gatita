//
//  RobloxProject.swift
//  Gatita
//

import Foundation

/// Whether a folder is a Roblox project, worked out from its file names alone.
nonisolated struct RobloxProject: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// A Rojo project: a `*.project.json` file says how the folder becomes a place.
        case rojo
        /// Script files named the way Roblox Studio's Script Sync and Rojo name them, such as `Main.server.luau`.
        case scriptFiles
    }

    let kind: Kind
    /// The file that gave it away, relative to the folder.
    let evidence: String

    /// How many folders down to look (the folder itself, then three levels), and how many entries to look at in all.
    /// The project bar runs this each time the folder changes, so a huge folder must not keep it busy.
    static let maxLevels = 4
    static let maxEntries = 2_000

    /// A Rojo project file found anywhere in the search wins, since it says exactly how the folder becomes a game.
    /// Otherwise the first script file found, looking at the nearest folders first. Hidden folders, symbolic links,
    /// and `node_modules` are skipped.
    static func detect(in folder: URL) -> RobloxProject? {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        var scripts: RobloxProject?
        var level: [(directory: URL, path: String)] = [(folder, "")]
        var visited = 0
        for _ in 0..<maxLevels where !level.isEmpty {
            var below: [(directory: URL, path: String)] = []
            for (directory, path) in level {
                let entries = (try? FileManager.default.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
                for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    visited += 1
                    if visited > maxEntries { return scripts }
                    let name = entry.lastPathComponent
                    let relative = path.isEmpty ? name : path + "/" + name
                    let values = try? entry.resourceValues(forKeys: Set(keys))
                    if values?.isDirectory == true {
                        if values?.isSymbolicLink != true, name != "node_modules" { below.append((entry, relative)) }
                    } else if name.hasSuffix(".project.json") {
                        return RobloxProject(kind: .rojo, evidence: relative)
                    } else if scripts == nil, isScriptFile(name) {
                        scripts = RobloxProject(kind: .scriptFiles, evidence: relative)
                    }
                }
            }
            level = below
        }
        return scripts
    }

    /// Runs off the main actor, since the project bar calls it from a view each time the folder changes.
    @concurrent
    static func load(in folder: URL) async -> RobloxProject? {
        detect(in: folder)
    }

    /// What the chip says when you point at it: what was found, how edits to these files reach Roblox Studio, and
    /// where to find the skill. Edits reach Studio only while Rojo is serving or Script Sync is syncing, which Gatita
    /// can't see, so the text says so instead of promising it.
    func summary(studioConnected: Bool) -> String {
        var lines: [String]
        switch kind {
        case .rojo:
            lines = ["Rojo project (\(evidence)).",
                     "Gatita edits these files, and they reach Studio while Rojo is serving the project."]
        case .scriptFiles:
            lines = ["Roblox script files (\(evidence)).",
                     "Gatita edits these files, and they reach Studio while it is syncing this folder with Script Sync."]
        }
        if studioConnected { lines.append("Studio tools are connected, so Gatita can also work in the open place.") }
        lines.append("Type /roblox to add the Roblox skill.")
        return lines.joined(separator: " ")
    }

    /// Whether a file is named for a script's type before its extension, such as `Main.server.luau` or `Boot.client.lua`.
    /// A name must come first, so `server.luau` and the hidden `.server.luau` are not scripts of that type.
    private static func isScriptFile(_ name: String) -> Bool {
        let parts = name.lowercased().split(separator: ".")
        guard parts.count >= 3, ["luau", "lua"].contains(parts[parts.count - 1]) else { return false }
        return ["server", "client", "local", "legacy", "plugin"].contains(parts[parts.count - 2])
    }
}

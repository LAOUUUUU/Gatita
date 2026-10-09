//
//  Plugins.swift
//  Gatita
//

import Foundation

/// A plugin folder's plugin.json: extra skills and extra allowed commands.
nonisolated struct PluginManifest: Codable, Sendable {
    struct PluginSkill: Codable, Sendable {
        let id: String
        let name: String
        let instructions: String
    }

    let name: String
    let description: String?
    let skills: [PluginSkill]?
    let commands: [String]?
}

/// What a plugin is, for the Settings list and the "@" menu.
nonisolated struct PluginDetail: Identifiable, Sendable {
    let name: String
    let description: String
    let skillNames: [String]
    let commands: [String]

    var id: String { name }
}

/// Everything the loaded plugins contribute.
nonisolated struct LoadedPlugins: Sendable {
    var names: [String] = []
    var details: [PluginDetail] = []
    var skills: [Skill] = []
    var commands: [[String]] = []
}

nonisolated enum Plugins {
    /// ~/Library/Application Support/Gatita/plugins
    static var defaultDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Gatita/plugins", isDirectory: true)
    }

    /// Reads every folder that holds a plugin.json. A folder that fails to parse is skipped.
    static func load(from directory: URL) -> LoadedPlugins {
        var loaded = LoadedPlugins()
        let folders = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("plugin.json")),
                  let manifest = try? JSONDecoder().decode(PluginManifest.self, from: data) else { continue }

            loaded.names.append(manifest.name)
            loaded.details.append(PluginDetail(name: manifest.name,
                                               description: manifest.description ?? "",
                                               skillNames: (manifest.skills ?? []).map(\.name),
                                               commands: manifest.commands ?? []))
            for skill in manifest.skills ?? [] {
                loaded.skills.append(Skill(id: "plugin:\(manifest.name):\(skill.id)",
                                           name: skill.name,
                                           instructions: skill.instructions))
            }
            for line in manifest.commands ?? [] {
                if let args = CommandPolicy.argv(line) {
                    loaded.commands.append(args)
                }
            }
        }
        return loaded
    }
}

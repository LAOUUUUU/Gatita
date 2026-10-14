//
//  AppSettings.swift
//  Gatita
//

import Foundation

/// The settings the app remembers between launches. The API key is not here; it stays in the Keychain.
nonisolated struct AppSettings: Codable, Equatable, Sendable {
    var projectRoot: String
    var model: String
    var connectors: [String]
    var allowWrites: Bool
    var allowCommands: Bool
    var skillID: String
    var mode: GatitaMode
    var keepAwake: Bool
    var transcriptView: TranscriptView
    var customInstructions: String
    /// Pressing ⌘ twice opens the quick panel. Mac only.
    var doubleCommandOpensPanel: Bool
    /// Pressing ⌘ twice starts with a screenshot, as Claude's quick entry does. Mac only.
    var doubleCommandTakesScreenshot: Bool
    /// Gatita remembers facts about you across chats (memory.json). On unless turned off.
    var memoryEnabled: Bool
    /// Each command waits for your answer before it runs. On unless turned off.
    var askBeforeCommands: Bool
    /// Commands you chose "Always allow" for, by project folder, such as ["/Users/me/App": ["swift test"]].
    var commandRules: [String: [String]]

    init(projectRoot: String = "",
         model: String = "gatita-7.1-max",
         connectors: [String] = [],
         allowWrites: Bool = false,
         allowCommands: Bool = false,
         skillID: String = "none",
         mode: GatitaMode = .code,
         keepAwake: Bool = false,
         transcriptView: TranscriptView = .normal,
         customInstructions: String = "",
         doubleCommandOpensPanel: Bool = true,
         doubleCommandTakesScreenshot: Bool = true,
         memoryEnabled: Bool = true,
         askBeforeCommands: Bool = true,
         commandRules: [String: [String]] = [:]) {
        self.projectRoot = projectRoot
        self.model = model
        self.connectors = connectors
        self.allowWrites = allowWrites
        self.allowCommands = allowCommands
        self.skillID = skillID
        self.mode = mode
        self.keepAwake = keepAwake
        self.transcriptView = transcriptView
        self.customInstructions = customInstructions
        self.doubleCommandOpensPanel = doubleCommandOpensPanel
        self.doubleCommandTakesScreenshot = doubleCommandTakesScreenshot
        self.memoryEnabled = memoryEnabled
        self.askBeforeCommands = askBeforeCommands
        self.commandRules = commandRules
    }

    private enum CodingKeys: String, CodingKey {
        case projectRoot, model, connectors, allowWrites, allowCommands, skillID, mode, keepAwake, transcriptView, customInstructions
        case doubleCommandOpensPanel, doubleCommandTakesScreenshot, memoryEnabled, askBeforeCommands, commandRules
    }

    /// Missing keys take their defaults, so a settings file from an older version still loads.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        projectRoot = try values.decodeIfPresent(String.self, forKey: .projectRoot) ?? defaults.projectRoot
        model = try values.decodeIfPresent(String.self, forKey: .model) ?? defaults.model
        connectors = try values.decodeIfPresent([String].self, forKey: .connectors) ?? defaults.connectors
        allowWrites = try values.decodeIfPresent(Bool.self, forKey: .allowWrites) ?? defaults.allowWrites
        allowCommands = try values.decodeIfPresent(Bool.self, forKey: .allowCommands) ?? defaults.allowCommands
        skillID = try values.decodeIfPresent(String.self, forKey: .skillID) ?? defaults.skillID
        mode = try values.decodeIfPresent(GatitaMode.self, forKey: .mode) ?? defaults.mode
        keepAwake = try values.decodeIfPresent(Bool.self, forKey: .keepAwake) ?? defaults.keepAwake
        transcriptView = try values.decodeIfPresent(TranscriptView.self, forKey: .transcriptView) ?? defaults.transcriptView
        customInstructions = try values.decodeIfPresent(String.self, forKey: .customInstructions) ?? defaults.customInstructions
        doubleCommandOpensPanel = try values.decodeIfPresent(Bool.self, forKey: .doubleCommandOpensPanel)
            ?? defaults.doubleCommandOpensPanel
        doubleCommandTakesScreenshot = try values.decodeIfPresent(Bool.self, forKey: .doubleCommandTakesScreenshot)
            ?? defaults.doubleCommandTakesScreenshot
        memoryEnabled = try values.decodeIfPresent(Bool.self, forKey: .memoryEnabled) ?? defaults.memoryEnabled
        askBeforeCommands = try values.decodeIfPresent(Bool.self, forKey: .askBeforeCommands) ?? defaults.askBeforeCommands
        commandRules = try values.decodeIfPresent([String: [String]].self, forKey: .commandRules) ?? defaults.commandRules
    }
}

/// Reads and writes the settings file, a readable JSON file in the app's folder.
nonisolated enum SettingsStore {
    /// ~/Library/Application Support/Gatita/settings.json
    static var defaultFile: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Gatita/settings.json")
    }

    static func load(from file: URL) -> AppSettings {
        guard let data = try? Data(contentsOf: file),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return settings
    }

    static func save(_ settings: AppSettings, to file: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(settings) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    /// The saved file. Before the file exists, the values the app used to keep in UserDefaults are copied across once.
    static func loadOrMigrate(file: URL, defaults: UserDefaults) -> AppSettings {
        if FileManager.default.fileExists(atPath: file.path) {
            return load(from: file)
        }
        var migrated = AppSettings()
        migrated.projectRoot = defaults.string(forKey: "projectRoot") ?? ""
        migrated.model = defaults.string(forKey: "model") ?? migrated.model
        migrated.connectors = (defaults.stringArray(forKey: "connectors") ?? []).sorted()
        return migrated
    }
}

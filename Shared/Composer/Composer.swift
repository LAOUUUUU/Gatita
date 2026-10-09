//
//  Composer.swift
//  Gatita
//

import Foundation

/// What the word being typed can start: "/" for a skill (only at the start of a message),
/// "@" for a project file, and "!" for a plugin.
nonisolated enum ComposerTrigger: Equatable, Sendable {
    case skill
    case file
    case plugin
}

nonisolated struct ComposerToken: Equatable, Sendable {
    let trigger: ComposerTrigger
    /// The text typed after the trigger character.
    let query: String
}

/// Logic for the input box's "/" and "@" menus. Pure, so it can be tested without the UI.
nonisolated enum Composer {
    /// The word at the end of the text, if it is a "/" or "@" token that is still being typed.
    static func activeToken(in text: String) -> ComposerToken? {
        guard let last = text.last, last != " ", last != "\n" else { return nil }
        let words = text.split(whereSeparator: { $0 == " " || $0 == "\n" })
        guard let word = words.last, let first = word.first else { return nil }

        switch first {
        case "/":
            // Skills are chosen only when "/" starts the message.
            guard words.count == 1 else { return nil }
            return ComposerToken(trigger: .skill, query: String(word.dropFirst()))
        case "@":
            return ComposerToken(trigger: .file, query: String(word.dropFirst()))
        case "!":
            return ComposerToken(trigger: .plugin, query: String(word.dropFirst()))
        default:
            return nil
        }
    }

    /// Replaces the token being typed with `replacement`, followed by a space.
    static func replacingActiveToken(in text: String, with replacement: String) -> String {
        guard activeToken(in: text) != nil,
              let range = text.range(of: #"\S+$"#, options: .regularExpression) else { return text }
        return text.replacingCharacters(in: range, with: replacement + " ")
    }

    static func skills(matching query: String, in skills: [Skill]) -> [Skill] {
        let needle = query.lowercased()
        return skills.filter { needle.isEmpty || $0.id.lowercased().contains(needle) || $0.name.lowercased().contains(needle) }
    }

    static func files(matching query: String, in paths: [String], limit: Int = 30) -> [String] {
        let needle = query.lowercased()
        return Array(paths.filter { needle.isEmpty || $0.lowercased().contains(needle) }.prefix(limit))
    }

    /// The "@path" words in a message, without the "@". Each one is read as a project file when sending.
    static func mentions(in text: String) -> [String] {
        marked(text, with: "@")
    }

    /// The "!name" words in a message, without the "!". Each one is matched to a plugin when sending.
    static func pluginMentions(in text: String) -> [String] {
        marked(text, with: "!")
    }

    private static func marked(_ text: String, with prefix: Character) -> [String] {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" }).compactMap { word in
            guard word.first == prefix, word.count > 1 else { return nil }
            return String(word.dropFirst())
        }
    }
}

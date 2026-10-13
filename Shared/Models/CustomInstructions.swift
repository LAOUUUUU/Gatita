//
//  CustomInstructions.swift
//  Gatita
//

import Foundation

/// Your own instructions, which Gatita reads before every reply. The skill's instructions come after them.
nonisolated enum CustomInstructions {
    /// The most of your own instructions Gatita reads, so they can't crowd out the chat.
    static let maxCharacters = 4_000

    /// The text added to each reply: your instructions, then the skill's. Nil when there is neither.
    static func systemText(custom: String, skill: String?) -> String? {
        let mine = String(custom.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxCharacters))
        let theirs = skill?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let parts = [mine, theirs].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }
}

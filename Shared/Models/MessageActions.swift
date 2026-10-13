//
//  MessageActions.swift
//  Gatita
//

import Foundation

/// What the buttons under a reply do.
nonisolated enum MessageAction: Equatable, Sendable {
    case copy
    case fork
    case pin
    case reply
}

nonisolated enum MessageActions {
    /// The most lines a quote holds. A longer reply is quoted for its first lines and then "> …".
    static let maxQuotedLines = 6

    /// The text as a quote: each line starts with "> ", and a blank line follows.
    static func quote(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var quoted = lines.prefix(maxQuotedLines).map { "> " + $0 }
        if lines.count > maxQuotedLines {
            quoted.append("> …")
        }
        return quoted.joined(separator: "\n") + "\n\n"
    }

    /// The messages up to and including the one with this id. Nil when no message has it.
    static func fork(_ messages: [ChatMessage], upTo id: UUID) -> [ChatMessage]? {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return nil }
        return Array(messages[...index])
    }
}

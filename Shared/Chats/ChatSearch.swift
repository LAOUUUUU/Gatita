//
//  ChatSearch.swift
//  Gatita
//

import SwiftUI

/// The sidebar search: a chat matches when its title or any question or reply holds the words, in any case.
/// Errors and notices are left out, since they are Gatita's, not the chat's.
nonisolated enum ChatSearch {
    static let snippetLength = 70
    static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
    /// The roles whose messages are searched.
    static let roles: Set<String> = ["user", "assistant"]

    static func matches(_ chat: Conversation, query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return chat.title.range(of: query, options: options) != nil || snippet(in: chat.messages, query: query) != nil
    }

    /// The words around the first match, on one line, with "…" where text was cut. Nil when nothing matches.
    static func snippet(in messages: [ChatMessage], query: String) -> String? {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        for message in messages where roles.contains(message.role) {
            let text = message.content
            guard let range = text.range(of: query, options: options) else { continue }
            let at = text.distance(from: text.startIndex, to: range.lowerBound)
            let startOffset = max(0, at - max(0, (snippetLength - query.count) / 2))
            let endOffset = min(text.count, startOffset + snippetLength)
            let start = text.index(text.startIndex, offsetBy: startOffset)
            let end = text.index(text.startIndex, offsetBy: endOffset)
            let piece = text[start..<end].replacingOccurrences(of: "\n", with: " ")
            return (startOffset > 0 ? "…" : "") + piece + (endOffset < text.count ? "…" : "")
        }
        return nil
    }
}

/// ⌘F in the open chat: every match in order, stepping through them, and marking them in the text.
nonisolated enum FindInChat {
    struct Match: Equatable {
        let messageID: UUID
        /// Which match inside its message, from 0.
        let number: Int
    }

    /// The color behind a match: Gatita's orange, see-through.
    static let highlight = Color(red: 0.96, green: 0.42, blue: 0.14).opacity(0.45)

    static func matches(in messages: [ChatMessage], query: String) -> [Match] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        var found: [Match] = []
        for message in messages where ChatSearch.roles.contains(message.role) {
            var rest = message.content.startIndex..<message.content.endIndex
            var number = 0
            while let range = message.content.range(of: query, options: ChatSearch.options, range: rest) {
                found.append(Match(messageID: message.id, number: number))
                number += 1
                rest = range.upperBound..<message.content.endIndex
            }
        }
        return found
    }

    /// The match after (or before) `index`, going round from the last to the first. 0 when there are none.
    static func step(from index: Int, by offset: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((index + offset) % count + count) % count
    }

    /// The text with a color behind every match of the query.
    static func highlighted(_ text: AttributedString, query: String) -> AttributedString {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return text }
        var text = text
        var rest = text.startIndex..<text.endIndex
        while let range = text[rest].range(of: query, options: ChatSearch.options) {
            text[range].backgroundColor = highlight
            rest = range.upperBound..<text.endIndex
        }
        return text
    }
}

extension EnvironmentValues {
    /// The words ⌘F is looking for, marked in the replies. Empty while nothing is being found.
    @Entry var findHighlight = ""
}

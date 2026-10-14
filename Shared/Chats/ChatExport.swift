//
//  ChatExport.swift
//  Gatita
//

import Foundation

/// A saved chat as a Markdown file: the questions and answers in order, without errors or notices.
nonisolated enum ChatExport {
    static func markdown(title: String, messages: [ChatMessage], date: Date = Date()) -> String {
        let day = ISO8601DateFormatter.string(from: date, timeZone: .current, formatOptions: [.withFullDate])
        var parts = ["# \(title)", "_Exported from Gatita on \(day)._"]
        for message in messages where message.role == "user" || message.role == "assistant" {
            guard !message.content.isEmpty else { continue }
            parts.append("## \(message.role == "user" ? "You" : "Gatita")\n\n\(message.content)")
        }
        return parts.joined(separator: "\n\n") + "\n"
    }

    /// The chat's title as a file name: characters that file systems refuse become dashes.
    static func fileName(for title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Gatita chat.md" }
        let safe = trimmed.map { "/\\:?*\"<>|".contains($0) ? "-" : String($0) }.joined()
        return String(safe.prefix(80)) + ".md"
    }
}

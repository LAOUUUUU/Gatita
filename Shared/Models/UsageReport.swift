//
//  UsageReport.swift
//  Gatita
//

import Foundation

/// The /usage command: the token counts of the replies the server reported, and the text the chat shows.
nonisolated enum UsageReport {
    struct Totals: Equatable, Sendable {
        let promptTokens: Int
        let completionTokens: Int
        let replies: Int
        /// How many of those replies were estimated rather than counted by the server.
        var estimatedReplies: Int = 0
    }

    /// Adds up the usage of the assistant replies that have a count. Replies without one are not counted.
    static func totals(of messages: [ChatMessage]) -> Totals {
        var prompt = 0
        var completion = 0
        var replies = 0
        var estimated = 0
        for message in messages where message.role == "assistant" {
            guard let usage = message.usage else { continue }
            prompt += usage.promptTokens
            completion += usage.completionTokens
            replies += 1
            if usage.isEstimate { estimated += 1 }
        }
        return Totals(promptTokens: prompt, completionTokens: completion, replies: replies, estimatedReplies: estimated)
    }

    /// The text the chat shows for /usage.
    static func text(thisChat: Totals, allChats: Totals) -> String {
        guard allChats.replies > 0 else {
            return "Usage\nNo token counts yet. Gatita has not reported usage for any reply."
        }
        let chatLine = thisChat.replies > 0 ? "This chat: \(line(thisChat))" : "This chat: no counted replies yet"
        return [
            "Usage",
            chatLine,
            "All saved chats: \(line(allChats))",
            "Only replies where the server reported usage are counted.",
        ].joined(separator: "\n")
    }

    /// Whether a message is the /usage command, and nothing else.
    static func isCommand(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines) == "/usage"
    }

    private static func line(_ totals: Totals) -> String {
        let replies = totals.replies == 1 ? "1 reply" : "\(totals.replies) replies"
        let estimated = totals.estimatedReplies > 0 ? " (\(totals.estimatedReplies) estimated)" : ""
        return "\(TokenUsage.grouped(totals.promptTokens)) in · \(TokenUsage.grouped(totals.completionTokens)) out, from \(replies)\(estimated)"
    }
}

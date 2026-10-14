//
//  MessageActions.swift
//  Gatita
//

import Foundation

/// What the buttons under a message do.
nonisolated enum MessageAction: Equatable, Sendable {
    case copy
    case fork
    case pin
    case reply
    /// Answer the same question again, with this model, or the chosen one when nil.
    case regenerate(model: String?)
    /// Read the reply out loud, or stop reading it.
    case speak
    /// Send a question again with new words. Everything after it is replaced.
    case edit(String)
    /// Put back the files the reply wrote or edited.
    case undoChanges
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

    /// To answer a reply anew: the messages before its question, and the question to send again.
    /// Nil when the reply is unknown or no question comes before it.
    static func regenerate(_ messages: [ChatMessage], replyID: UUID) -> (kept: [ChatMessage], question: ChatMessage)? {
        guard let reply = messages.firstIndex(where: { $0.id == replyID }),
              let asked = messages[..<reply].lastIndex(where: { $0.role == "user" }) else { return nil }
        return (Array(messages[..<asked]), messages[asked])
    }

    /// To send a question again with new words: the messages before it, and the new question, which keeps the
    /// old one's attached files and pictures. What its @mentions and connectors added is not kept: `mentions` is
    /// that part made again from the new words, so a file named before and not now is not sent.
    /// Nil for an empty edit, or a message that is not a question.
    static func edit(_ messages: [ChatMessage], questionID: UUID, newText: String,
                     mentions: String = "") -> (kept: [ChatMessage], question: ChatMessage)? {
        let text = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let index = messages.firstIndex(where: { $0.id == questionID }),
              messages[index].role == "user" else { return nil }
        let old = messages[index]
        let context = [mentions, attachedFiles(in: old.attachedContext)].filter { !$0.isEmpty }.joined(separator: "\n\n")
        return (Array(messages[..<index]),
                ChatMessage(role: "user", content: text, attachedContext: context, images: old.images))
    }

    /// The part of a question's context that came from files dropped on it ("File <name> (attached):"). It always
    /// comes after the part made from @mentions and connectors. Empty when no file was dropped.
    static func attachedFiles(in context: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: #"(?:^|\n\n)(File [^\n]* \(attached\):\n)"#),
              let match = expression.firstMatch(in: context, range: NSRange(context.startIndex..., in: context)),
              let start = Range(match.range(at: 1), in: context) else { return "" }
        return String(context[start.lowerBound...])
    }

    /// The newest reply that has finished and has text.
    static func lastReply(_ messages: [ChatMessage]) -> ChatMessage? {
        messages.last { $0.role == "assistant" && !$0.isStreaming && !$0.content.isEmpty }
    }
}

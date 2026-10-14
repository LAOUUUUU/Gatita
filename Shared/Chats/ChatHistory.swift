//
//  ChatHistory.swift
//  Gatita
//

import Foundation

/// One saved chat: its messages, and when it last changed.
nonisolated struct Conversation: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var updatedAt: Date
    var messages: [ChatMessage]
    /// A title Gatita wrote for the chat. Shown instead of the first question once it exists.
    var customTitle: String? = nil
    /// The mode the chat was started in. A chat stays in that mode. Nil in chats saved before modes existed.
    var mode: GatitaMode? = nil
    /// Shown at the top of the sidebar. Nil (not pinned) in chats saved before pins existed.
    var pinned: Bool? = nil
    /// The sidebar folder the chat is in, or nil for none.
    var folder: String? = nil

    var title: String {
        customTitle ?? ChatHistory.title(for: messages)
    }

    var preview: String {
        ChatHistory.preview(for: messages)
    }
}

/// Titles, previews, and the chat history file. Chats are kept on this Mac, in the app's folder.
nonisolated enum ChatHistory {
    private static let titleLength = 48
    private static let previewLength = 80
    private static let generatedTitleLength = 60

    /// ~/Library/Application Support/Gatita/chats.json
    static var defaultFile: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Gatita/chats.json")
    }

    /// Whether a chat has anything of its own to keep: a question or a reply. A chat that only holds a notice,
    /// such as the /usage counts, or an error is not saved.
    static func isWorthSaving(_ messages: [ChatMessage]) -> Bool {
        messages.contains { $0.role == "user" || $0.role == "assistant" }
    }

    /// The first question, shortened, or "New chat" when there is none.
    static func title(for messages: [ChatMessage]) -> String {
        guard let question = messages.first(where: { $0.role == "user" })?
            .content.trimmingCharacters(in: .whitespacesAndNewlines), !question.isEmpty else {
            return "New chat"
        }
        return question.count > titleLength ? String(question.prefix(titleLength)) + "…" : question
    }

    /// The first line of words in the latest reply, without Markdown marks or code, shortened.
    static func preview(for messages: [ChatMessage]) -> String {
        guard let reply = messages.last(where: { $0.role == "assistant" && !$0.content.isEmpty }) else { return "" }
        let firstLine = SpeechText.plain(from: reply.content)
            .components(separatedBy: "\n")
            .first { !$0.isEmpty && $0 != "Code block skipped." && $0 != "Chart skipped." } ?? ""
        return String(firstLine.trimmingCharacters(in: .whitespaces).prefix(previewLength))
    }

    /// The prompt that asks Gatita for a short title from the first question and the first answer.
    static func titlePrompt(messages: [ChatMessage]) -> String {
        let question = messages.first { $0.role == "user" }?.content ?? ""
        let answer = messages.first { $0.role == "assistant" && !$0.content.isEmpty }?.content ?? ""
        return """
        Write a short title for this chat, 2 to 5 words, in the same language as the question. Reply with the title only: no quotes, no full stop.

        Question: \(String(question.prefix(600)))

        Answer: \(String(answer.prefix(600)))
        """
    }

    /// A title from Gatita's reply: the first line, without quotes, a "Title:" label, or closing punctuation.
    static func cleanTitle(_ reply: String) -> String? {
        let firstLine = reply.components(separatedBy: "\n")
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        var line = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.lowercased().hasPrefix("title:") {
            line = String(line.dropFirst("title:".count))
        }
        line = line.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`*#").union(.whitespacesAndNewlines))
        while let last = line.last, ".!?:".contains(last) {
            line.removeLast()
        }
        line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }
        return String(line.prefix(generatedTitleLength))
    }

    /// The chats with one chat saved: its messages, mode, and time replaced, and its title, pin, and folder kept.
    /// A chat saved for the first time is added at the end.
    static func updated(_ chats: [Conversation], id: UUID, messages: [ChatMessage], mode: GatitaMode,
                        at date: Date) -> [Conversation] {
        var chats = chats
        let old = chats.first { $0.id == id }
        chats.removeAll { $0.id == id }
        var chat = Conversation(id: id, updatedAt: date, messages: messages, mode: mode)
        chat.customTitle = old?.customTitle
        chat.pinned = old?.pinned
        chat.folder = old?.folder
        chats.append(chat)
        return chats
    }

    static func load(from file: URL) -> [Conversation] {
        guard let data = try? Data(contentsOf: file),
              let chats = try? JSONDecoder().decode([Conversation].self, from: data) else { return [] }
        return chats
    }

    static func save(_ chats: [Conversation], to file: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(chats) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}

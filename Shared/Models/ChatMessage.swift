//
//  ChatMessage.swift
//  Gatita
//
//  Created by LAOUUU on 2026-10-08.
//


import Foundation

/// A picture the user attached. Its bytes go to the model as a data URL, and it stays in the saved chat.
struct ChatImage: Codable, Hashable {
    let name: String
    let mimeType: String
    let data: Data
}

struct ChatMessage: Identifiable, Codable, Hashable {
    let id: UUID
    let role: String   // "user" or "assistant"
    var content: String
    /// The model's thinking text, when it streams any.
    var reasoning: String
    /// Tool calls the model made while answering, in order.
    var activities: [ToolActivity]
    var isStreaming: Bool
    var errorText: String?
    /// Text the model receives with this message (attached files, plugin summaries). Not shown in the bubble.
    var attachedContext: String
    /// Pictures attached to this message. Optional, so chats saved before pictures existed still load.
    var images: [ChatImage]?

    /// The pictures attached to this message, or none.
    var attachedImages: [ChatImage] { images ?? [] }

    init(id: UUID = UUID(),
         role: String,
         content: String,
         reasoning: String = "",
         activities: [ToolActivity] = [],
         isStreaming: Bool = false,
         errorText: String? = nil,
         attachedContext: String = "",
         images: [ChatImage]? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.reasoning = reasoning
        self.activities = activities
        self.isStreaming = isStreaming
        self.errorText = errorText
        self.attachedContext = attachedContext
        self.images = images
    }

    /// What the model receives: the message plus its attachments.
    var sentText: String {
        attachedContext.isEmpty ? content : content + "\n\n" + attachedContext
    }
}

struct ToolActivity: Identifiable, Codable, Hashable {
    let id: String          // the tool call id from the API
    let name: String
    let arguments: String
    /// nil while the tool is still running.
    var result: String?
    /// The diff of the file this tool changed. Shown in place of the raw arguments.
    var change: FileChange?
    var startedAt: Date?
    var finishedAt: Date?
}

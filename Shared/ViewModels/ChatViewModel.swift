//
//  ChatViewModel.swift
//  Gatita
//
//  Created by LAOUUU on 2026-10-08.
//


import Foundation
import Observation

@Observable
@MainActor
final class ChatViewModel {
    static let models = ["gatita-7.1-max", "gatita-7.1-mini"]
    private static let modelNames = ["gatita-7.1-max": "Gatita 7.1 Max", "gatita-7.1-mini": "Gatita 7.1 Mini"]

    static func displayName(for model: String) -> String {
        modelNames[model] ?? model
    }

    private static let keyAccount = "gatita-api-key"
    /// Largest amount of attached file text sent with one message.
    private static let attachmentLimit = 60_000

    /// Local log and failure reports. Nothing leaves this Mac.
    let log = AppLog(directory: AppLog.defaultDirectory)
    /// Local event counts. Nothing leaves this Mac.
    let analytics = Analytics(file: Analytics.defaultFile)
    /// Skills, commands, and summaries from plugin folders in Application Support/Gatita/plugins.
    private(set) var plugins = Plugins.load(from: Plugins.defaultDirectory)

    var messages: [ChatMessage] = []
    var isSending = false
    var errorMessage: String?
    /// Replies that finished. Shown by the badge at the top right until it is cleared.
    var finishedReplies = 0
    /// A question Gatita asked. Answer it by sending a message.
    var pendingQuestion: String?
    /// What the prompt box holds, so the starter prompts can fill it.
    var draft = ""
    /// Saved chats. Kept in chats.json on this Mac.
    private(set) var conversations: [Conversation]
    /// The saved chat the messages on screen belong to, once it has been saved.
    private(set) var currentConversationID: UUID?
    private var sendTask: Task<Void, Never>?
    /// Chats that already have a title, or a title on the way, so each chat is titled once.
    private var titledChats: Set<UUID> = []

    /// Saved in the Keychain; each change is written as you type.
    var apiKey: String {
        didSet { persistAPIKey() }
    }
    /// Folder Gatita may list and read. Empty means plain chat with no file tools. Saved in the settings file.
    var projectRoot: String {
        didSet { persistSettings() }
    }
    /// Saved in the settings file. Turn it off when you don't want Gatita editing files.
    var allowWrites: Bool {
        didSet { persistSettings() }
    }
    /// Commands that do run stay inside the macOS sandbox. Saved in the settings file.
    var allowCommands: Bool = false {
        didSet { persistSettings() }
    }
    /// Connectors turned on for the whole chat in Settings. Mentioning !name turns one on for a single message.
    var connectors: Set<String> {
        didSet { persistSettings() }
    }
    /// The skill whose instructions are added to each reply. Chosen with "/" or the skill menu.
    var skillID: String = Skills.none {
        didSet { persistSettings() }
    }
    /// Saved in the settings file.
    var model: String {
        didSet { persistSettings() }
    }

    /// Built-in skills plus any plugin skills.
    var skills: [Skill] {
        Skills.all + plugins.skills
    }

    init(apiKey: String,
         projectRoot: String? = nil,
         allowWrites: Bool = ProcessInfo.processInfo.environment["GATITA_ALLOW_WRITES"] == "1") {
        let saved = SettingsStore.loadOrMigrate(file: SettingsStore.defaultFile, defaults: .standard)
        self.apiKey = KeychainStore.read(account: Self.keyAccount) ?? apiKey
        self.projectRoot = projectRoot ?? (saved.projectRoot.isEmpty
            ? (ProcessInfo.processInfo.environment["GATITA_PROJECT_ROOT"] ?? "")
            : saved.projectRoot)
        self.allowWrites = allowWrites || saved.allowWrites
        self.allowCommands = saved.allowCommands
        self.connectors = Set(saved.connectors)
        self.skillID = saved.skillID
        self.model = Self.models.contains(saved.model) ? saved.model : Self.models[0]
        self.conversations = ChatHistory.load(from: ChatHistory.defaultFile)
        persistSettings()
    }

    /// Project tools for the current folder, or nil when no folder is set.
    var projectTools: ProjectTools? {
        makeTools(connectors: connectors)
    }

    /// Project tools with the given connectors on.
    private func makeTools(connectors enabled: Set<String>) -> ProjectTools? {
        let path = projectRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        return ProjectTools(root: URL(fileURLWithPath: (path as NSString).expandingTildeInPath),
                            allowWrites: allowWrites,
                            allowCommands: allowCommands,
                            commands: CommandPolicy.builtIn + plugins.commands,
                            logDirectory: log.directory,
                            connectors: enabled)
    }

    /// Rereads the plugin folders, so a new plugin shows up without relaunching.
    func reloadPlugins() {
        plugins = Plugins.load(from: Plugins.defaultDirectory)
    }

    /// Every file path in the project, for the "@" menu.
    func projectFilePaths() -> [String] {
        guard let tree = try? projectTools?.tree() else { return [] }
        return Self.filePaths(in: tree)
    }

    /// Starts a reply in the background. Use stop() to cancel it.
    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        errorMessage = nil
        pendingQuestion = nil

        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            errorMessage = "Add your Gatita API key in Settings first."
            return
        }

        messages.append(ChatMessage(role: "user", content: trimmed, attachedContext: attachments(for: trimmed)))
        let reply = ChatMessage(role: "assistant", content: "", isStreaming: true)
        messages.append(reply)
        let replyID = reply.id
        let history = Array(messages.dropLast())

        isSending = true
        analytics.count("message_sent")
        log.info("message sent with model \(model) and skill \(skillID)")
        let instructions = skills.first { $0.id == skillID }?.instructions
        let mentionedConnectors = Set(Composer.pluginMentions(in: trimmed).filter { Connectors.connector(named: $0) != nil })
        let client = GatitaClient(apiKey: key, model: model,
                                  tools: makeTools(connectors: connectors.union(mentionedConnectors)),
                                  extraInstructions: instructions)
        sendTask = Task {
            do {
                try await client.stream(messages: history) { event in
                    self.apply(event, toReply: replyID)
                }
                if self.pendingQuestion == nil { self.finishedReplies += 1 }
            } catch {
                let cancelled = Task.isCancelled || (error as? URLError)?.code == .cancelled
                if cancelled {
                    self.analytics.count("stopped")
                    self.updateReply(replyID) { $0.errorText = "Stopped." }
                } else {
                    let report = self.recordFailure(kind: "reply", message: error.localizedDescription,
                                                    details: ["model: \(self.model)", "project: \(self.projectRoot)"])
                    let note = report.map { " Report saved: \($0)" } ?? ""
                    self.updateReply(replyID) { $0.errorText = error.localizedDescription + note }
                }
            }
            // A reply with leaked control tokens is not kept. The question stays, so it can be sent again.
            if let index = self.messages.firstIndex(where: { $0.id == replyID }),
               ReplyCheck.isCorrupted(self.messages[index].content) {
                let raw = self.messages[index].content
                self.messages.remove(at: index)
                self.analytics.count("reply_garbled")
                let report = self.recordFailure(kind: "reply-garbled",
                                                message: "The reply contained control tokens and was dropped.",
                                                details: ["model: \(self.model)", "sample: \(String(raw.prefix(400)))"])
                self.errorMessage = "Gatita's reply came back garbled, so it was not kept. Send the message again."
                    + (report.map { " Report saved: \($0)" } ?? "")
            }
            self.updateReply(replyID) { $0.isStreaming = false }
            self.isSending = false
            self.sendTask = nil
            if !self.messages.isEmpty {
                self.saveCurrentChat()
                if let id = self.currentConversationID { self.requestTitle(forChat: id) }
            }
        }
    }

    /// One reply with no tools, used for writing text such as a pull request description.
    func oneShot(_ prompt: String) async throws -> String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ToolError("Add your Gatita API key in Settings first.") }
        return try await GatitaClient(apiKey: key, model: model)
            .send(messages: [ChatMessage(role: "user", content: prompt)])
    }

    /// Cancels the reply in progress. The partial reply stays on screen, marked as stopped.
    func stop() {
        sendTask?.cancel()
    }

    /// Stops any reply in progress, saves the chat on screen, and starts a fresh one.
    func newChat() {
        stop()
        saveCurrentChat()
        messages = []
        currentConversationID = nil
        errorMessage = nil
    }

    /// Opens a saved chat. The chat on screen is saved first.
    func openChat(_ id: UUID) {
        guard let chat = conversations.first(where: { $0.id == id }) else { return }
        stop()
        saveCurrentChat()
        messages = chat.messages
        currentConversationID = id
        errorMessage = nil
        requestTitle(forChat: id)
    }

    /// Removes a saved chat. If it is the one on screen, the screen goes blank.
    func deleteChat(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        if currentConversationID == id {
            stop()
            messages = []
            currentConversationID = nil
        }
        ChatHistory.save(conversations, to: ChatHistory.defaultFile)
    }

    /// Writes the chat on screen into the history, if it has any messages.
    func saveCurrentChat() {
        guard !messages.isEmpty else { return }
        let id = currentConversationID ?? UUID()
        currentConversationID = id
        conversations.removeAll { $0.id == id }
        conversations.append(Conversation(id: id, updatedAt: Date(), messages: messages))
        ChatHistory.save(conversations, to: ChatHistory.defaultFile)
    }

    /// For each "@path" in a message, the text of that project file; for each "!name", that plugin's summary. Anything else is ignored.
    private func attachments(for text: String) -> String {
        var parts: [String] = []
        for path in Composer.mentions(in: text) {
            if let tools = projectTools, let contents = try? tools.readText(path) {
                parts.append("File \(path):\n```\n\(contents.prefix(Self.attachmentLimit))\n```")
            }
        }
        for name in Composer.pluginMentions(in: text) {
            if let connector = Connectors.connector(named: name) {
                parts.append("Connector \(connector.name) is on for this message. Tools: \(connector.tools.joined(separator: ", ")).")
            } else if let plugin = plugins.details.first(where: { $0.name == name }) {
                parts.append("Plugin \(plugin.name): \(plugin.description) Skills: \(plugin.skillNames.joined(separator: ", ")). Commands: \(plugin.commands.joined(separator: ", ")).")
            }
        }
        return String(parts.joined(separator: "\n\n").prefix(Self.attachmentLimit))
    }

    private static func filePaths(in nodes: [FileNode]) -> [String] {
        nodes.flatMap { node in node.isDirectory ? filePaths(in: node.children ?? []) : [node.path] }
    }

    private func apply(_ event: StreamEvent, toReply id: UUID) {
        switch event {
        case .toolStarted(_, let name, let arguments):
            analytics.count("tool:\(name)")
            log.info("tool \(name) \(arguments.prefix(200))")
        case .toolFinished(_, let name, let result):
            if result.hasPrefix("error:") {
                analytics.count("tool_error")
                _ = recordFailure(kind: "tool-\(name)", message: result, details: ["tool: \(name)"])
            }
        case .question(let text):
            analytics.count("question")
            log.info("Gatita asked: \(text)")
            pendingQuestion = text
        case .text, .reasoning:
            break
        }

        updateReply(id) { reply in
            switch event {
            case .text(let piece):
                reply.content += piece
            case .reasoning(let piece):
                reply.reasoning += piece
            case .toolStarted(let callID, let name, let arguments):
                reply.activities.append(ToolActivity(id: callID, name: name, arguments: arguments, result: nil))
            case .question:
                break
            case .toolFinished(let callID, _, let result):
                if let position = reply.activities.firstIndex(where: { $0.id == callID }) {
                    reply.activities[position].result = result
                }
            }
        }
    }

    /// Clears the finished count once the user has seen it.
    func acknowledgeFinished() {
        finishedReplies = 0
    }

    /// Clears the question once the user has read it.
    func dismissQuestion() {
        pendingQuestion = nil
    }

    /// Asks Gatita for a short title for a chat once it has a question and an answer. If that fails, the question stays as the title.
    private func requestTitle(forChat id: UUID) {
        guard !titledChats.contains(id),
              let chat = conversations.first(where: { $0.id == id }),
              chat.customTitle == nil,
              chat.messages.contains(where: { $0.role == "assistant" && !$0.content.isEmpty }) else { return }
        titledChats.insert(id)
        let prompt = ChatHistory.titlePrompt(messages: chat.messages)
        Task {
            guard let reply = try? await self.oneShot(prompt),
                  let title = ChatHistory.cleanTitle(reply),
                  let index = self.conversations.firstIndex(where: { $0.id == id }) else { return }
            self.conversations[index].customTitle = title
            ChatHistory.save(self.conversations, to: ChatHistory.defaultFile)
        }
    }

    /// Logs a failure, writes a report Gatita can read, and returns the report's path.
    private func recordFailure(kind: String, message: String, details: [String]) -> String? {
        analytics.count("failure:\(kind)")
        log.error("\(kind) failed: \(message)")
        return log.recordFailure(kind: kind, message: message, details: details)
    }

    /// Looks the reply up by ID, so a reply that was cleared while streaming is simply ignored.
    private func updateReply(_ id: UUID, _ change: (inout ChatMessage) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        change(&messages[index])
    }

    /// Writes every remembered setting to the settings file. The API key is never part of it.
    private func persistSettings() {
        SettingsStore.save(AppSettings(projectRoot: projectRoot, model: model, connectors: connectors.sorted(),
                                       allowWrites: allowWrites, allowCommands: allowCommands, skillID: skillID),
                           to: SettingsStore.defaultFile)
    }

    private func persistAPIKey() {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty {
            KeychainStore.delete(account: Self.keyAccount)
        } else {
            KeychainStore.save(key, account: Self.keyAccount)
        }
    }
}

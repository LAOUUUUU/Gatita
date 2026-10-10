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
    /// Background commands and subagents started in this run of the app. Shown in the activity panel.
    let tasks = TaskRegistry()
    /// Nearby devices running Gatita, for sending chats to one of them.
    let remoteMac = RemoteMacBrowser()
    /// The code this device types in to pair with a Mac. Kept in the Keychain, not in the settings file.
    var remoteCode: String {
        didSet { saveRemoteCode() }
    }
    /// Until when devices may pair with this device. Nil when pairing is closed.
    /// Not saved, so pairing closes when the app quits.
    private(set) var pairingOpenUntil: Date?
    /// The code for the current pairing window. A new one is made each time pairing opens. Not saved.
    private(set) var pairingCode: String?

    var isPairingOpen: Bool {
        (pairingOpenUntil ?? .distantPast) > Date()
    }

    /// Opens pairing for a few minutes, with a new code. Devices pair only with that code.
    func openPairing(minutes: Double = 5) {
        pairingCode = PairingCode.make()
        pairingOpenUntil = Date().addingTimeInterval(minutes * 60)
    }

    func closePairing() {
        pairingCode = nil
        pairingOpenUntil = nil
    }

    var messages: [ChatMessage] = []
    var isSending = false
    var errorMessage: String?
    /// Replies that finished. Shown by the badge at the top right until it is cleared.
    var finishedReplies = 0
    /// A question Gatita asked. Answer it by sending a message.
    var pendingQuestion: String?
    /// What the prompt box holds, so the starter prompts can fill it.
    var draft = ""
    /// Files dropped on the prompt box. Their text goes to Gatita with the next message.
    var droppedFiles: [DroppedFile] = []
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
    /// Keeps the Mac from sleeping on its own while Gatita is open. Saved in the settings file. Mac only.
    var keepAwake: Bool = false {
        didSet {
            persistSettings()
            applyKeepAwake()
        }
    }
    #if os(macOS)
    private let sleepGuard = SleepGuard()
    #endif
    /// Chat or Code. Only Code has project tools. Saved in the settings file.
    var mode: GatitaMode {
        didSet { persistSettings() }
    }
    /// The mode the chat on screen was started in. Saved with the chat, so it stays in that mode.
    private var sessionMode: GatitaMode = .code
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
        // Only the Mac has projects, so every other device is always in Chat.
        let startMode: GatitaMode = HostPolicy.current == .mac ? saved.mode : .chat
        self.mode = startMode
        self.sessionMode = startMode
        self.keepAwake = saved.keepAwake
        self.remoteCode = KeychainStore.read(account: "remote-code") ?? ""
        self.model = Self.models.contains(saved.model) ? saved.model : Self.models[0]
        self.conversations = ChatHistory.load(from: ChatHistory.defaultFile)
        persistSettings()
        applyKeepAwake()
    }

    private func applyKeepAwake() {
        #if os(macOS)
        sleepGuard.set(keepAwake)
        #endif
    }

    /// Whether a project folder is set for this host.
    var hasProjectFolder: Bool {
        HostPolicy.projectRoot(projectRoot) != nil
    }

    /// The project folder as tools, for browsing and attaching files. Not limited by the mode.
    var projectTools: ProjectTools? {
        makeTools(connectors: [], mode: .code)
    }

    /// Tools for one reply. Chat gets no project tools. Code gets them when a folder is set.
    /// A connector runs only if the host and the mode allow it.
    private func makeTools(connectors enabled: Set<String>, mode: GatitaMode) -> ProjectTools? {
        let folder = mode.usesProjectTools ? HostPolicy.projectRoot(projectRoot) : nil
        let connectorsOn = mode.connectors(HostPolicy.connectors(enabled), hasProject: folder != nil)
        guard folder != nil || !connectorsOn.isEmpty else { return nil }
        return ProjectTools(root: folder,
                            allowWrites: folder != nil && allowWrites,
                            allowCommands: folder != nil && allowCommands,
                            commands: CommandPolicy.builtIn + plugins.commands,
                            logDirectory: log.directory,
                            connectors: connectorsOn,
                            allowsReports: mode.usesReportTools)
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
        guard !trimmed.isEmpty || !droppedFiles.isEmpty, !isSending else { return }
        errorMessage = nil
        pendingQuestion = nil

        // A message that breaks a local safety rule is refused here, and Gatita is never asked.
        if let flag = SafetyFlags.match(trimmed) {
            messages.append(ChatMessage(role: "user", content: trimmed))
            addErrorBubble("Gatita did not answer this message.",
                           detail: "Reason: \(flag.title). A local safety rule stopped it, so Gatita was not asked.")
            analytics.count("safety_flag")
            log.info("message refused by local safety rule \(flag.id)")
            saveCurrentChat()
            return
        }

        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let viaPairedDevice = mode == .remote && HostPolicy.current != .mac
        guard !key.isEmpty || viaPairedDevice else {
            errorMessage = "Add your Gatita API key in Settings first."
            return
        }

        let files = droppedFiles
        droppedFiles = []
        let content = trimmed.isEmpty ? "Attached: " + files.map(\.name).joined(separator: ", ") : trimmed
        let context = [attachments(for: trimmed), DroppedFile.context(for: files, limit: Self.attachmentLimit)]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        let images = files.compactMap(\.image)
        messages.append(ChatMessage(role: "user", content: content, attachedContext: context,
                                    images: images.isEmpty ? nil : images))
        let reply = ChatMessage(role: "assistant", content: "", isStreaming: true)
        messages.append(reply)
        let replyID = reply.id
        let history = Array(messages.dropLast().filter { $0.role != "error" })

        isSending = true
        analytics.count("message_sent")
        log.info("message sent with model \(model) and skill \(skillID)")
        let instructions = skills.first { $0.id == skillID }?.instructions
        if viaPairedDevice {
            sendThroughPairedDevice(history.last?.sentText ?? trimmed, replyID: replyID)
            return
        }
        let mentionedConnectors = Set(Composer.pluginMentions(in: trimmed).filter { Connectors.connector(named: $0) != nil })
        let client = GatitaClient(apiKey: key, model: model,
                                  tools: makeTools(connectors: connectors.union(mentionedConnectors), mode: mode),
                                  extraInstructions: instructions, tasks: tasks)
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
                    self.addErrorBubble(Self.headline(for: error), detail: Self.detail(for: error, report: report))
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
                let lines = ["Send the message again.", report.map { "Report saved: \($0)" }].compactMap { $0 }
                self.addErrorBubble("Gatita's reply came back garbled, so it was not kept.", detail: lines.joined(separator: "\n"))
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

    /// Adds files dropped on the prompt box. A file Gatita cannot read is reported and left out.
    func attachDroppedFiles(_ urls: [URL]) {
        for url in urls {
            do {
                droppedFiles.append(try DroppedFile.read(url))
                log.info("attached dropped file \(url.lastPathComponent)")
            } catch {
                log.info("could not attach dropped file \(url.lastPathComponent): \(error.localizedDescription)")
                errorMessage = error.localizedDescription
            }
        }
    }

    /// A long paste becomes a Markdown attachment, so the box stays short.
    func attachPastedText(_ text: String) {
        let file = DroppedFile.pasted(text, among: droppedFiles)
        droppedFiles.append(file)
        log.info("long paste attached as \(file.name)")
    }

    func removeDroppedFile(_ id: UUID) {
        droppedFiles.removeAll { $0.id == id }
    }

    /// Cancels the reply in progress. The partial reply stays on screen, marked as stopped.
    func stop() {
        sendTask?.cancel()
    }

    /// The saved chats that belong to one mode. Chat and Code keep their own lists.
    func conversations(in mode: GatitaMode) -> [Conversation] {
        conversations.filter { ($0.mode ?? .code) == mode }
    }

    /// Changes the mode. The chat on screen is saved in the mode it was started in, and a fresh chat starts in the new one.
    func switchMode(to newMode: GatitaMode) {
        guard newMode != mode else { return }
        stop()
        saveCurrentChat()
        messages = []
        currentConversationID = nil
        errorMessage = nil
        mode = newMode
        sessionMode = newMode
    }

    /// Stops any reply in progress, saves the chat on screen, and starts a fresh one in the current mode.
    func newChat() {
        stop()
        saveCurrentChat()
        messages = []
        currentConversationID = nil
        errorMessage = nil
        sessionMode = mode
    }

    /// Opens a saved chat. The chat on screen is saved first. Opening a chat switches to the mode it belongs to.
    func openChat(_ id: UUID) {
        guard let chat = conversations.first(where: { $0.id == id }) else { return }
        stop()
        saveCurrentChat()
        messages = chat.messages
        currentConversationID = id
        errorMessage = nil
        sessionMode = chat.mode ?? .code
        mode = sessionMode
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
        // Saving again keeps the title that was already generated for this chat.
        let title = conversations.first { $0.id == id }?.customTitle
        conversations.removeAll { $0.id == id }
        var chat = Conversation(id: id, updatedAt: Date(), messages: messages, mode: sessionMode)
        chat.customTitle = title
        conversations.append(chat)
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
            if let connector = Connectors.connector(named: name), HostPolicy.allows(connector),
               mode.allows(connector: connector.id, hasProject: hasProjectFolder) {
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
        case .fileChanged(_, let change):
            analytics.count("file_changed")
            log.info("changed \(change.path): +\(change.added) -\(change.removed)")
        case .safetyStop:
            analytics.count("safety_stop")
            log.info("reply stopped by a safety filter")
            addErrorBubble("Gatita stopped this reply for safety.")
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
                reply.activities.append(ToolActivity(id: callID, name: name, arguments: arguments, result: nil,
                                                     startedAt: Date()))
            case .question, .safetyStop:
                break
            case .fileChanged(let callID, let change):
                if let position = reply.activities.firstIndex(where: { $0.id == callID }) {
                    reply.activities[position].change = change
                }
            case .toolFinished(let callID, _, let result):
                if let position = reply.activities.firstIndex(where: { $0.id == callID }) {
                    reply.activities[position].result = result
                    reply.activities[position].finishedAt = Date()
                }
            }
        }
    }

    /// Sends a chat to the connected device, which answers with its own key and no project tools.
    private func sendThroughPairedDevice(_ prompt: String, replyID: UUID) {
        sendTask = Task {
            do {
                let answer = try await self.remoteMac.ask(prompt) { piece in
                    self.updateReply(replyID) { $0.content += piece }
                }
                self.updateReply(replyID) { $0.content = answer }
                if self.pendingQuestion == nil { self.finishedReplies += 1 }
            } catch {
                self.analytics.count("paired_device_unreachable")
                self.log.error("could not reach the paired device: \(error.localizedDescription)")
                self.messages.removeAll { $0.id == replyID && $0.content.isEmpty }
                self.addErrorBubble("Gatita could not reach your Mac.", detail: error.localizedDescription)
            }
            self.updateReply(replyID) { $0.isStreaming = false }
            self.isSending = false
            self.sendTask = nil
            self.saveCurrentChat()
        }
    }

    /// The pairing code is kept in the Keychain. An empty code removes it.
    private func saveRemoteCode() {
        let code = remoteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if code.isEmpty {
            _ = KeychainStore.delete(account: "remote-code")
        } else {
            _ = KeychainStore.save(code, account: "remote-code")
        }
    }

    /// Shows an error as a red message after the latest one. It is not sent back to Gatita.
    private func addErrorBubble(_ headline: String, detail: String? = nil) {
        messages.append(ChatMessage(role: "error", content: headline, errorText: detail))
    }

    /// The first line of an error bubble.
    private static func headline(for error: Error) -> String {
        if let gatita = error as? GatitaError, case .http(let status, _) = gatita {
            return "Gatita could not answer (HTTP \(status))."
        }
        return "Gatita could not answer."
    }

    /// The detail under the headline. A "Reason:" line appears only when the server gave one.
    private static func detail(for error: Error, report: String?) -> String? {
        var lines: [String] = []
        if let gatita = error as? GatitaError, case .http(_, let body) = gatita {
            if let reason = GatitaError.serverReason(in: body) {
                lines.append("Reason: \(reason)")
            }
        } else {
            lines.append(error.localizedDescription)
        }
        if let report {
            lines.append("Report saved: \(report)")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
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
                                       allowWrites: allowWrites, allowCommands: allowCommands, skillID: skillID, mode: mode, keepAwake: keepAwake),
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

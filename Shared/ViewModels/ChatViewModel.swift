//
//  ChatViewModel.swift
//  Gatita
//
//  Created by LAOUUU on 2026-10-08.
//


import Foundation
import Observation
#if os(macOS)
import AppKit
#endif

@Observable
@MainActor
final class ChatViewModel {
    static let models = ["gatita-7.1-max", "gatita-7.1-mini"]
    /// True in the app the unit tests run in, which leaves the real Keychain alone.
    private static let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
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
    /// Whether this device is online. The chat shows a banner while it is not.
    let connectivity = Connectivity()
    /// Reads replies aloud.
    let speaker = Speaker()
    /// Sends a notification when a reply or a long task finishes while Gatita is not in front.
    let notifier = ReplyNotifier()
    #if os(macOS)
    /// Stops the background commands when Gatita quits.
    @ObservationIgnored private var quitObserver: NSObjectProtocol?
    #endif

    /// Whether the menu bar item shows: only while something long runs in the background, or while the Mac is
    /// kept awake. A finished reply is a notification instead.
    var showsMenuBarItem: Bool {
        tasks.runningCount > 0 || !runningSchedules.isEmpty || keepAwake
    }
    /// Types what you say into the prompt box.
    let voice = VoiceInput()
    /// Skills you wrote in Settings. Kept in my-skills.json.
    private(set) var mySkills: [Skill] = MySkills.load(from: MySkills.defaultFile)
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
    /// A question Gatita asked. Answer it by sending a message.
    var pendingQuestion: String?
    /// When the reply in progress will be sent again after the API's rate limit. Nil when it is not waiting.
    private(set) var retryAt: Date?
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
    /// How much of a reply the chat shows. Saved in the settings file.
    var transcriptView: TranscriptView {
        didSet { persistSettings() }
    }
    /// Your own instructions, read before every reply. Saved in the settings file.
    var customInstructions: String {
        didSet { persistSettings() }
    }
    /// Whether Gatita remembers facts about you across chats. Saved in the settings file.
    var memoryEnabled: Bool {
        didSet { persistSettings() }
    }
    /// What Gatita remembers, from memory.json. The model changes it with its tools, so it is read again after
    /// each reply and when Settings, Memory opens.
    private(set) var memories: [MemoryFact] = MemoryStore.load(from: MemoryStore.defaultFile)
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
    /// Each command waits for your answer before it runs. Saved in the settings file.
    var askBeforeCommands: Bool {
        didSet { persistSettings() }
    }
    /// The commands you chose "Always allow" for, by project folder. Saved in the settings file.
    var commandRules: [String: [String]] {
        didSet { persistSettings() }
    }
    /// The command waiting for your answer, shown over the chat.
    private(set) var pendingCommand: CommandApproval.Request?
    @ObservationIgnored private var commandAnswer: CheckedContinuation<CommandApproval.Decision, Never>?
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
    /// Pressing ⌘ twice opens the quick panel. Saved in the settings file. Mac only.
    var doubleCommandOpensPanel: Bool = true {
        didSet {
            persistSettings()
            #if os(macOS)
            QuickPanelController.shared.setDoubleCommand(doubleCommandOpensPanel, viewModel: self)
            #endif
        }
    }
    /// Pressing ⌘ twice starts with a screenshot. Saved in the settings file. Mac only.
    var doubleCommandTakesScreenshot: Bool = true {
        didSet { persistSettings() }
    }
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

    /// Built-in skills, then yours, then any plugin skills.
    var skills: [Skill] {
        Skills.all + mySkills + plugins.skills
    }

    init(apiKey: String,
         projectRoot: String? = nil,
         allowWrites: Bool = ProcessInfo.processInfo.environment["GATITA_ALLOW_WRITES"] == "1") {
        let saved = SettingsStore.loadOrMigrate(file: SettingsStore.defaultFile, defaults: .standard)
        // The app the tests run in never reads the real Keychain: the tests need no key, and a new build can make
        // macOS ask for the Keychain password, which would stop the test run until someone answers.
        self.apiKey = Self.isTesting ? apiKey : KeychainStore.read(account: Self.keyAccount) ?? apiKey
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
        self.transcriptView = saved.transcriptView
        self.customInstructions = saved.customInstructions
        self.memoryEnabled = saved.memoryEnabled
        self.askBeforeCommands = saved.askBeforeCommands
        self.commandRules = saved.commandRules
        self.doubleCommandOpensPanel = saved.doubleCommandOpensPanel
        self.doubleCommandTakesScreenshot = saved.doubleCommandTakesScreenshot
        self.remoteCode = Self.isTesting ? "" : KeychainStore.read(account: "remote-code") ?? ""
        self.model = Self.models.contains(saved.model) ? saved.model : Self.models[0]
        self.conversations = ChatHistory.load(from: ChatHistory.defaultFile)
        persistSettings()
        applyKeepAwake()
        CheckpointStore.removeOld(in: CheckpointStore.defaultDirectory, now: Date())
        undoableReplies = CheckpointStore.replyIDs(in: CheckpointStore.defaultDirectory)
        startScheduler()
        // Clicking a notification opens its chat. For the chat already on screen it only brings Gatita forward:
        // opening it again would stop its reply, and deny a command waiting for your answer.
        notifier.onOpenChat = { [weak self] id in
            guard let self, id != self.currentConversationID else { return }
            self.openChat(id)
        }
        IntentBridge.viewModel = self
        tasks.onTaskFinished = { [weak self] note in self?.notifier.post(note) }
        if !Self.isTesting {
            let servers = mcpServers
            Task { await mcp.connectAll(servers) }
        }
        #if os(macOS)
        quitObserver = MacLaunch.start(self)
        #endif
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
    /// A connector runs only if the host and the mode allow it. Connected MCP servers' tools are offered in both
    /// modes; `mcpOnlyTrusted` keeps only trusted servers', for places that can't ask before a call.
    private func makeTools(connectors enabled: Set<String>, mode: GatitaMode, mcpOnlyTrusted: Bool = false) -> ProjectTools? {
        let folder = mode.usesProjectTools ? HostPolicy.projectRoot(projectRoot) : nil
        let connectorsOn = mode.connectors(HostPolicy.connectors(enabled), hasProject: folder != nil)
        let mcpTools = mcp.toolHelp(onlyTrusted: mcpOnlyTrusted)
        guard folder != nil || !connectorsOn.isEmpty || memoryEnabled || !mcpTools.isEmpty else { return nil }
        return ProjectTools(root: folder,
                            allowWrites: folder != nil && allowWrites,
                            allowCommands: folder != nil && allowCommands,
                            commands: CommandPolicy.builtIn + plugins.commands,
                            logDirectory: log.directory,
                            connectors: connectorsOn,
                            allowsReports: mode.usesReportTools,
                            memoryFile: memoryEnabled ? MemoryStore.defaultFile : nil,
                            extraToolHelp: mcpTools)
    }

    /// Runs MCP tool calls for a client. With `onlyTrusted`, a call to a server you did not trust is refused, since
    /// nothing can ask you first there.
    private func mcpRunner(onlyTrusted: Bool) -> @MainActor @Sendable (String, String) async -> String {
        { [weak self] name, block in
            guard let self else { return "error: Gatita is closing." }
            if onlyTrusted, !self.mcp.isTrusted(name) {
                return "error: \(name) can only be used in a Gatita chat, where the user can allow it first."
            }
            return await self.mcp.call(name, block: block)
        }
    }

    // MARK: - MCP servers

    let mcp = MCPHub()
    /// The servers in mcp.json, in name order.
    private(set) var mcpServers: [MCPServerConfig] = MCPConfig.load(from: MCPConfig.defaultFile)

    /// Adds a server, or changes the one named `old`, saves mcp.json, and starts it again unless it is turned off.
    func saveMCPServer(_ server: MCPServerConfig, replacing old: String? = nil) {
        mcpServers.removeAll { $0.name == server.name || $0.name == old }
        mcpServers.append(server)
        mcpServers.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        MCPConfig.save(mcpServers, to: MCPConfig.defaultFile)
        Task {
            if let old, old != server.name { await mcp.disconnect(old) }
            if server.disabled {
                await mcp.disconnect(server.name)
            } else {
                await mcp.connect(server)
            }
        }
    }

    func removeMCPServer(_ name: String) {
        mcpServers.removeAll { $0.name == name }
        MCPConfig.save(mcpServers, to: MCPConfig.defaultFile)
        Task { await mcp.disconnect(name) }
    }

    /// Trusts a server (its tools run without asking) or stops trusting it, without restarting it.
    func setMCPServer(_ name: String, trusted: Bool) {
        guard let index = mcpServers.firstIndex(where: { $0.name == name }) else { return }
        mcpServers[index].trusted = trusted
        MCPConfig.save(mcpServers, to: MCPConfig.defaultFile)
        mcp.update(mcpServers[index])
    }

    func setMCPServer(_ name: String, enabled: Bool) {
        guard var server = mcpServers.first(where: { $0.name == name }) else { return }
        server.disabled = !enabled
        saveMCPServer(server)
    }

    func reconnectMCPServer(_ name: String) {
        guard let server = mcpServers.first(where: { $0.name == name }) else { return }
        Task { await mcp.connect(server) }
    }

    /// The servers in Claude Desktop's settings that Gatita does not have yet, to show before importing them.
    func claudeDesktopServersToImport() -> [MCPServerConfig] {
        guard let data = try? Data(contentsOf: MCPConfig.claudeDesktopFile),
              let found = try? MCPConfig.parse(data) else { return [] }
        return MCPConfig.importable(found, existing: mcpServers)
    }

    /// Adds servers, as Import does once you confirmed. Each one starts right away.
    func importMCPServers(_ servers: [MCPServerConfig]) {
        for server in servers { saveMCPServer(server) }
    }

    /// The instructions added to every reply: how the chat draws Markdown, then your instructions and the
    /// skill's, then what Gatita remembers about you.
    private func systemText(skill: String?) -> String {
        let remembered = memoryEnabled ? MemoryStore.instructions(MemoryStore.load(from: MemoryStore.defaultFile)) : nil
        let parts = [CustomInstructions.systemText(custom: customInstructions, skill: skill), remembered].compactMap { $0 }
        return ReplyFormat.system(with: parts.isEmpty ? nil : parts.joined(separator: "\n\n"))
    }

    // MARK: - Scheduled prompts (Mac)

    /// Prompts Gatita runs on its own. Saved in schedules.json.
    private(set) var scheduledPrompts: [ScheduledPrompt] = ScheduleStore.load(from: ScheduleStore.defaultFile)
    /// The scheduled prompts running now.
    private(set) var runningSchedules: Set<UUID> = []
    @ObservationIgnored private var scheduleTimer: Timer?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    /// The chat folder scheduled runs are saved in.
    static let scheduledFolder = "Scheduled"

    func saveScheduledPrompt(_ prompt: ScheduledPrompt) {
        if let index = scheduledPrompts.firstIndex(where: { $0.id == prompt.id }) {
            scheduledPrompts[index] = prompt
        } else {
            scheduledPrompts.append(prompt)
        }
        ScheduleStore.save(scheduledPrompts, to: ScheduleStore.defaultFile)
    }

    func deleteScheduledPrompt(_ id: UUID) {
        scheduledPrompts.removeAll { $0.id == id }
        ScheduleStore.save(scheduledPrompts, to: ScheduleStore.defaultFile)
    }

    func runScheduledPromptNow(_ id: UUID) {
        guard let prompt = scheduledPrompts.first(where: { $0.id == id }), !runningSchedules.contains(id) else { return }
        Task { await runScheduled(prompt) }
    }

    /// Checks every minute, and when the Mac wakes, for scheduled prompts that are due (`ScheduleMath.decision`).
    private func startScheduler() {
        #if os(macOS)
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        scheduleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkSchedules() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkSchedules() }
        }
        checkSchedules()
        #endif
    }

    private func checkSchedules(now: Date = Date()) {
        for prompt in scheduledPrompts where !runningSchedules.contains(prompt.id) {
            let decision = ScheduleMath.decision(for: prompt, now: now)
            guard decision != .wait else { continue }
            var updated = prompt
            updated.lastRun = now
            saveScheduledPrompt(updated)
            if decision == .run {
                Task { await runScheduled(updated) }
            } else {
                log.info("scheduled prompt \(prompt.name) skipped: it was due more than 12 hours ago")
            }
        }
    }

    /// Runs a scheduled prompt in its own chat, saved in the Scheduled folder, and sends a notification either
    /// way. It never touches the chat on screen.
    private func runScheduled(_ prompt: ScheduledPrompt) async {
        runningSchedules.insert(prompt.id)
        defer { runningSchedules.remove(prompt.id) }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let question = ChatMessage(role: "user", content: prompt.prompt)
        var reply = ChatMessage(role: "assistant", content: "", respondedAt: Date())
        var notes: [ChatMessage] = []
        do {
            try IntentAnswer.check(question: prompt.prompt, key: key, online: connectivity.isOnline)
            let tools = makeTools(connectors: connectors, mode: prompt.mode)
            let recorder = tools.flatMap { tools in
                tools.allowWrites ? tools.root.map { CheckpointRecorder(replyID: reply.id, root: $0) } : nil
            }
            let client = GatitaClient(apiKey: key, model: model, tools: tools, extraInstructions: systemText(skill: nil),
                                      tasks: tasks,
                                      approveCommand: { [weak self] request in
                                          await self?.approveCommand(request, unattended: true) ?? .deny
                                      },
                                      checkpoints: recorder,
                                      mcp: mcpRunner(onlyTrusted: false))
            let asked = try await IntentAnswer.ask(prompt.prompt, with: client)
            reply.content = asked.answer
            if let note = MemoryStore.notice(asked.toolCalls) { notes.append(ChatMessage(role: "notice", content: note)) }
            reply.usage = TokenEstimate.usage(sentText: [prompt.prompt], reply: reply.content)
            if let recorder, !recorder.checkpoint.files.isEmpty { undoableReplies.insert(reply.id) }
            analytics.count("scheduled_run")
        } catch {
            // The same id, so undo still finds what the run changed before it failed.
            reply = ChatMessage(id: reply.id, role: "error", content: "The scheduled prompt did not finish: \(error.localizedDescription)")
            log.error("scheduled prompt \(prompt.name) failed: \(error.localizedDescription)")
        }
        let id = UUID()
        conversations = ChatHistory.updated(conversations, id: id, messages: [question, reply] + notes, mode: prompt.mode, at: Date())
        if let index = conversations.firstIndex(where: { $0.id == id }) {
            conversations[index].customTitle = ScheduleMath.chatTitle(name: prompt.name, at: Date())
            conversations[index].folder = Self.scheduledFolder
        }
        ChatHistory.save(conversations, to: ChatHistory.defaultFile)
        let note = reply.role == "error"
            ? Notifier.failed(chatTitle: prompt.name, reason: reply.content)
            : Notifier.scheduledFinished(name: prompt.name, reply: reply.content)
        notifier.post(note, chatID: id, always: true)
    }

    // MARK: - Checkpoints

    /// Replies whose file changes can be undone.
    private(set) var undoableReplies: Set<UUID> = CheckpointStore.replyIDs(in: CheckpointStore.defaultDirectory)
    /// A reply whose undo found files changed since, waiting for you to say whether to undo anyway.
    var undoConflict: UndoConflict?

    struct UndoConflict: Equatable {
        let replyID: UUID
        let files: [String]
    }

    /// Puts back the files a reply wrote or edited. Without `force`, files changed since stop it, and
    /// `undoConflict` asks you first.
    func undoChanges(_ replyID: UUID, force: Bool) {
        guard let checkpoint = CheckpointStore.load(replyID, in: CheckpointStore.defaultDirectory) else {
            undoableReplies.remove(replyID)
            return
        }
        let result = CheckpointStore.undo(checkpoint, force: force)
        if !result.conflicts.isEmpty, !force {
            undoConflict = UndoConflict(replyID: replyID, files: result.conflicts)
            return
        }
        undoConflict = nil
        CheckpointStore.remove(replyID, in: CheckpointStore.defaultDirectory)
        undoableReplies.remove(replyID)
        analytics.count("undid_changes")
        let files = result.restored.joined(separator: ", ")
        messages.append(ChatMessage(role: "notice", content: "Undid this reply's changes to \(result.restored.count) \(result.restored.count == 1 ? "file" : "files"): \(files). Changes made by commands are not undone."))
        saveCurrentChat()
    }

    // MARK: - Asking before commands

    /// The key for this project's "Always allow" rules: its folder's path.
    private var projectKey: String {
        HostPolicy.projectRoot(projectRoot)?.standardizedFileURL.path ?? projectRoot
    }

    /// The commands always allowed in this project, for Settings.
    var projectCommandRules: [String] {
        CommandApproval.rules(for: projectKey, in: commandRules)
    }

    /// Waits for your answer to a command, unless asking is off or you always allowed it in this project.
    /// While Gatita is not in front, a notification says a command is waiting.
    /// With `unattended` (a scheduled run), anything that would be asked is denied instead, since nobody is there
    /// to answer and the chat's one approval card must stay free for you.
    func approveCommand(_ request: CommandApproval.Request, unattended: Bool = false) async -> CommandApproval.Decision {
        let trusted = request.rule.hasPrefix("mcp__") && mcp.isTrusted(request.rule)
        if let decided = CommandApproval.decision(for: request, askBeforeCommands: askBeforeCommands,
                                                  rules: projectCommandRules, trustedMCP: trusted, unattended: unattended) {
            return decided
        }
        guard commandAnswer == nil else { return .deny }
        let title = conversations.first { $0.id == currentConversationID }?.title ?? ChatHistory.title(for: messages)
        notifier.post(Notifier.commandWaiting(chatTitle: title, command: request.command), chatID: currentConversationID)
        return await withCheckedContinuation { continuation in
            commandAnswer = continuation
            pendingCommand = request
        }
    }

    /// Your answer to the waiting command. "Always" saves its rule for this project first.
    func answerCommand(_ decision: CommandApproval.Decision) {
        guard let continuation = commandAnswer, let request = pendingCommand else { return }
        if decision == .allowAlways {
            commandRules = CommandApproval.adding(request.rule, project: projectKey, to: commandRules)
        }
        commandAnswer = nil
        pendingCommand = nil
        continuation.resume(returning: decision)
    }

    func removeCommandRule(_ rule: String) {
        let left = projectCommandRules.filter { $0 != rule }
        commandRules[projectKey] = left.isEmpty ? nil : left
    }

    // MARK: - Memory

    func reloadMemories() {
        memories = MemoryStore.load(from: MemoryStore.defaultFile)
    }

    /// Adds a fact by hand from Settings. Returns why it was not added, or nil.
    func addMemory(_ text: String) -> String? {
        switch MemoryStore.remember(text, in: MemoryStore.load(from: MemoryStore.defaultFile), at: Date()) {
        case .success(let facts):
            MemoryStore.save(facts, to: MemoryStore.defaultFile)
            memories = facts
            return nil
        case .failure(let problem):
            let reason = problem.localizedDescription
            return reason.prefix(1).uppercased() + reason.dropFirst() + "."
        }
    }

    func deleteMemory(_ id: UUID) {
        let facts = MemoryStore.load(from: MemoryStore.defaultFile).filter { $0.id != id }
        MemoryStore.save(facts, to: MemoryStore.defaultFile)
        memories = facts
    }

    func forgetAllMemories() {
        MemoryStore.save([], to: MemoryStore.defaultFile)
        memories = []
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

    /// Carries out a button under a reply.
    func performAction(_ action: MessageAction, on id: UUID) {
        guard let message = messages.first(where: { $0.id == id }) else { return }
        switch action {
        case .copy:
            Clipboard.copy(message.content)
        case .fork:
            forkChat(at: id)
        case .pin:
            togglePin(id)
        case .reply:
            draft += (draft.isEmpty ? "" : "\n") + MessageActions.quote(message.content)
        case .regenerate(let chosen):
            regenerate(id, model: chosen)
        case .speak:
            speaker.toggle(id: id, text: message.content)
        case .edit(let text):
            editAndResend(id, text: text)
        case .undoChanges:
            undoChanges(id, force: false)
        }
    }

    /// Copies the newest finished reply. For the keyboard shortcut.
    func copyLastReply() {
        if let reply = MessageActions.lastReply(messages) { Clipboard.copy(reply.content) }
    }

    /// Answers the newest reply anew. For the keyboard shortcut.
    func regenerateLastReply() {
        if let reply = MessageActions.lastReply(messages) { regenerate(reply.id) }
    }

    /// Reads the newest reply aloud, or stops reading. For the menu.
    func readLastReplyAloud() {
        if let reply = MessageActions.lastReply(messages) { speaker.toggle(id: reply.id, text: reply.content) }
    }

    /// Opens the skill menu in the prompt box by starting the draft with "/". For the keyboard shortcut.
    func startSkillPicker() {
        if !draft.hasPrefix("/") { draft = "/" + draft }
    }

    // MARK: - Quick panel

    /// A client for the quick panel: Chat mode, with the connectors you turned on, your instructions, and the skill
    /// picked in the panel. Nil without an API key.
    func quickPanelClient(skillID: String) -> GatitaClient? {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        let skill = skills.first { $0.id == skillID }?.instructions
        return GatitaClient(apiKey: key, model: model, tools: makeTools(connectors: connectors, mode: .chat, mcpOnlyTrusted: true),
                            extraInstructions: systemText(skill: skill), mcp: mcpRunner(onlyTrusted: true))
    }

    /// Answers a question from Shortcuts or Siri in Chat mode, with your connectors, instructions, and memory. The
    /// question and answer are saved as a new chat, without changing the chat on screen.
    func answerFromShortcut(_ question: String) async throws -> String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        try IntentAnswer.check(question: question, key: key, online: connectivity.isOnline)
        let client = GatitaClient(apiKey: key, model: model, tools: makeTools(connectors: connectors, mode: .chat, mcpOnlyTrusted: true),
                                  extraInstructions: systemText(skill: nil), mcp: mcpRunner(onlyTrusted: true))
        let (answer, toolCalls) = try await IntentAnswer.ask(question, with: client)
        var reply = ChatMessage(role: "assistant", content: answer, respondedAt: Date())
        reply.usage = TokenEstimate.usage(sentText: [question], reply: answer)
        let note = MemoryStore.notice(toolCalls).map { [ChatMessage(role: "notice", content: $0)] } ?? []
        conversations = ChatHistory.updated(conversations, id: UUID(),
                                            messages: [ChatMessage(role: "user", content: question), reply] + note,
                                            mode: .chat, at: Date())
        ChatHistory.save(conversations, to: ChatHistory.defaultFile)
        analytics.count("shortcut_question")
        return answer
    }

    /// Keeps a quick-panel question and answer as a new saved chat in Chat, and shows it.
    func adoptQuickChat(question: ChatMessage, answer: String) {
        if mode != .chat, HostPolicy.current == .mac {
            switchMode(to: .chat)
        } else {
            newChat()
        }
        var reply = ChatMessage(role: "assistant", content: answer, respondedAt: Date())
        reply.usage = TokenEstimate.usage(sentText: [question.sentText], reply: answer)
        messages = [question, reply]
        saveCurrentChat()
        if let id = currentConversationID { requestTitle(forChat: id) }
    }

    // MARK: - Saved chats: rename, export, delete all

    /// Gives a saved chat your own title. An empty title goes back to the one made from the first question.
    func renameChat(_ id: UUID, to title: String) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        conversations[index].customTitle = trimmed.isEmpty ? nil : String(trimmed.prefix(80))
        titledChats.insert(id)
        ChatHistory.save(conversations, to: ChatHistory.defaultFile)
    }

    // MARK: - Find in the chat (⌘F)

    /// Whether the find bar is open over the chat.
    var isFinding = false
    /// The words the find bar looks for. A new search starts at the first match.
    var findQuery = "" {
        didSet { findIndex = 0 }
    }
    /// The current match, among `findMatches`.
    var findIndex = 0
    /// Bumped by ⌘F, so the find bar takes the cursor even when it is already open.
    var findFocusRequests = 0

    /// Every match in the chat on screen, in order. None while the find bar is closed.
    var findMatches: [FindInChat.Match] {
        isFinding ? FindInChat.matches(in: messages, query: findQuery) : []
    }

    func startFinding() {
        isFinding = true
        findFocusRequests += 1
    }

    /// Goes to the next match, or the one before with -1, round the ends. Opens the find bar when it is closed.
    func findStep(_ offset: Int) {
        guard isFinding else { return startFinding() }
        findIndex = FindInChat.step(from: findIndex, by: offset, count: findMatches.count)
    }

    func stopFinding() {
        isFinding = false
        findQuery = ""
    }

    /// Pins a saved chat to the top of the sidebar, or unpins it.
    func togglePinChat(_ id: UUID) {
        changeChat(id) { $0.pinned = $0.pinned == true ? nil : true }
    }

    /// Moves a saved chat into a folder (made when the first chat goes in), or out of its folder with nil.
    func moveChat(_ id: UUID, toFolder name: String?) {
        changeChat(id) { $0.folder = name.flatMap(ChatSidebar.folderName) }
    }

    private func changeChat(_ id: UUID, _ change: (inout Conversation) -> Void) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        change(&conversations[index])
        ChatHistory.save(conversations, to: ChatHistory.defaultFile)
    }

    /// A saved chat as Markdown, and the file name to save it under.
    func exportChat(_ id: UUID) -> (text: String, fileName: String)? {
        if id == currentConversationID { saveCurrentChat() }
        guard let chat = conversations.first(where: { $0.id == id }) else { return nil }
        return (ChatExport.markdown(title: chat.title, messages: chat.messages), ChatExport.fileName(for: chat.title))
    }

    /// Removes every saved chat of one mode. If the chat on screen is one of them, the screen goes blank.
    func deleteAllChats(in mode: GatitaMode) {
        let doomed = Set(conversations(in: mode).map(\.id))
        if let current = currentConversationID, doomed.contains(current) {
            stop()
            messages = []
            currentConversationID = nil
        }
        conversations.removeAll { doomed.contains($0.id) }
        ChatHistory.save(conversations, to: ChatHistory.defaultFile)
        analytics.count("deleted_all_chats")
    }

    // MARK: - Your own skills

    /// Adds a skill of your own, or changes the one with the same id. It is saved right away.
    func saveMySkill(id: String?, name: String, instructions: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanText = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanText.isEmpty else { return }
        if let id, let index = mySkills.firstIndex(where: { $0.id == id }) {
            mySkills[index] = Skill(id: id, name: cleanName, instructions: cleanText)
        } else {
            let taken = Set(skills.map(\.id))
            mySkills.append(Skill(id: MySkills.id(for: cleanName, taken: taken), name: cleanName, instructions: cleanText))
        }
        MySkills.save(mySkills, to: MySkills.defaultFile)
    }

    func deleteMySkill(_ id: String) {
        mySkills.removeAll { $0.id == id }
        if skillID == id { skillID = Skills.none }
        MySkills.save(mySkills, to: MySkills.defaultFile)
    }

    /// Starts a new saved chat with the messages up to this reply. The chat it came from is kept as it was.
    private func forkChat(at id: UUID) {
        guard let kept = MessageActions.fork(messages, upTo: id) else { return }
        stop()
        saveCurrentChat()
        messages = kept
        currentConversationID = nil
        errorMessage = nil
        sessionMode = mode
        saveCurrentChat()
    }

    private func togglePin(_ id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].pinned = messages[index].pinned != true
        saveCurrentChat()
    }

    /// Shows the token totals as a notice in the chat. Gatita is not asked, and notices are not sent back to it.
    private func showUsage() {
        let otherChats = conversations.filter { $0.id != currentConversationID }.flatMap(\.messages)
        let text = UsageReport.text(thisChat: UsageReport.totals(of: messages),
                                    allChats: UsageReport.totals(of: otherChats + messages))
        messages.append(ChatMessage(role: "notice", content: text))
        saveCurrentChat()
    }

    /// Starts a reply in the background. Use stop() to cancel it.
    func send(_ text: String) {
        if voice.isListening { voice.stop() }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !droppedFiles.isEmpty, !isSending else { return }
        errorMessage = nil
        pendingQuestion = nil

        if UsageReport.isCommand(trimmed) {
            showUsage()
            return
        }

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
        // A message that is not sent goes back in the prompt box, which was cleared when it was sent.
        // With no internet the request cannot work, so it is not sent.
        if !viaPairedDevice, !connectivity.isOnline {
            draft = text
            showNoInternet()
            analytics.count("offline")
            log.info("message not sent: no internet access")
            return
        }
        guard !key.isEmpty || viaPairedDevice else {
            draft = text
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
        startReply(to: ChatMessage(role: "user", content: content, attachedContext: context,
                                   images: images.isEmpty ? nil : images),
                   key: key, viaPairedDevice: viaPairedDevice, model: model)
    }

    /// Whether a question can go to Gatita now. When it can't, the reason is shown, and false comes back.
    private func readyToSend() -> (key: String, viaPairedDevice: Bool)? {
        guard !isSending else { return nil }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let viaPairedDevice = mode == .remote && HostPolicy.current != .mac
        if !viaPairedDevice, !connectivity.isOnline {
            showNoInternet()
            return nil
        }
        guard !key.isEmpty || viaPairedDevice else {
            errorMessage = "Add your Gatita API key in Settings first."
            return nil
        }
        return (key, viaPairedDevice)
    }

    /// Answers a reply anew: its question is sent again, and the reply and everything after it are replaced.
    /// With a model, that one answer comes from it; the chosen model stays as it was.
    func regenerate(_ replyID: UUID, model chosen: String? = nil) {
        guard let ready = readyToSend(), let plan = MessageActions.regenerate(messages, replyID: replyID) else { return }
        errorMessage = nil
        let replaced = replacedCheckpoints(keeping: plan.kept)
        messages = plan.kept
        analytics.count("regenerated")
        startReply(to: plan.question, key: ready.key, viaPairedDevice: ready.viaPairedDevice, model: chosen ?? model,
                   inheriting: replaced)
    }

    /// Sends a question again with new words. The old question and everything after it are replaced.
    func editAndResend(_ questionID: UUID, text: String) {
        guard let ready = readyToSend(),
              let plan = MessageActions.edit(messages, questionID: questionID, newText: text,
                                             mentions: attachments(for: text.trimmingCharacters(in: .whitespacesAndNewlines)))
        else { return }
        errorMessage = nil
        let replaced = replacedCheckpoints(keeping: plan.kept)
        messages = plan.kept
        analytics.count("edited")
        startReply(to: plan.question, key: ready.key, viaPairedDevice: ready.viaPairedDevice, model: model,
                   inheriting: replaced)
    }

    /// The checkpoints of the replies a regenerate or edit drops, so the new reply can take over their file changes
    /// and its undo still puts them back.
    private func replacedCheckpoints(keeping kept: [ChatMessage]) -> [Checkpoint] {
        messages.dropFirst(kept.count).filter { undoableReplies.contains($0.id) }
            .compactMap { CheckpointStore.load($0.id, in: CheckpointStore.defaultDirectory) }
    }

    /// Adds the question and an empty reply, then streams the answer into the reply.
    private func startReply(to question: ChatMessage, key: String, viaPairedDevice: Bool, model: String,
                            inheriting replaced: [Checkpoint] = []) {
        // A question Gatita asked before is answered or replaced by this reply (regenerate and edit come here
        // without send), so it must not show, or be notified, again.
        pendingQuestion = nil
        let trimmed = question.content
        messages.append(question)
        let reply = ChatMessage(role: "assistant", content: "", isStreaming: true)
        messages.append(reply)
        let replyID = reply.id
        let history = Array(messages.dropLast().filter { $0.role != "error" && $0.role != "notice" })

        isSending = true
        analytics.count("message_sent")
        log.info("message sent with model \(model) and skill \(skillID)")
        let instructions = skills.first { $0.id == skillID }?.instructions
        if viaPairedDevice {
            sendThroughPairedDevice(history.last?.sentText ?? trimmed, replyID: replyID)
            return
        }
        let mentionedConnectors = Set(Composer.pluginMentions(in: trimmed).filter { Connectors.connector(named: $0) != nil })
        let tools = makeTools(connectors: connectors.union(mentionedConnectors), mode: mode)
        // What this reply writes and edits is recorded, so it can be undone, together with the changes of the replies
        // it replaces.
        let recorder: CheckpointRecorder? = if let tools, tools.allowWrites, let root = tools.root {
            CheckpointRecorder(replyID: replyID, root: root, inheriting: replaced)
        } else if let first = replaced.first {
            CheckpointRecorder(replyID: replyID, root: URL(fileURLWithPath: first.root), inheriting: replaced)
        } else {
            nil
        }
        for old in replaced {
            CheckpointStore.remove(old.replyID, in: CheckpointStore.defaultDirectory)
            undoableReplies.remove(old.replyID)
        }
        let client = GatitaClient(apiKey: key, model: model,
                                  tools: tools,
                                  extraInstructions: systemText(skill: instructions),
                                  tasks: tasks,
                                  approveCommand: { [weak self] request in
                                      await self?.approveCommand(request) ?? .deny
                                  },
                                  checkpoints: recorder,
                                  mcp: mcpRunner(onlyTrusted: false))
        notifier.prepare()
        sendTask = Task {
            var finished = false
            var failure: String?
            do {
                try await client.stream(messages: history) { event in
                    self.apply(event, toReply: replyID)
                }
                finished = true
            } catch GatitaError.garbled(let sample) {
                failure = "Gatita's reply came back garbled."
                self.messages.removeAll { $0.id == replyID }
                self.analytics.count("reply_garbled")
                let report = self.recordFailure(kind: "reply-garbled",
                                                message: "The reply contained control tokens and was stopped early.",
                                                details: ["model: \(self.model)", "sample: \(sample)"])
                let lines = ["Send the message again.", report.map { "Report saved: \($0)" }].compactMap { $0 }
                self.addErrorBubble(GatitaError.garbled(sample: sample).errorDescription ?? "Gatita's reply came back garbled.",
                                    detail: lines.joined(separator: "\n"))
            } catch {
                let cancelled = Task.isCancelled || (error as? URLError)?.code == .cancelled
                if cancelled {
                    self.analytics.count("stopped")
                    self.updateReply(replyID) { $0.errorText = "Stopped." }
                } else if NoInternet.matches(error, online: self.connectivity.isOnline) {
                    failure = NoInternet.headline
                    // Being offline is not a bug, so no failure report is written.
                    self.analytics.count("offline")
                    self.log.info("reply failed: no internet access (\(error.localizedDescription))")
                    self.showNoInternet()
                    self.removeIfEmpty(replyID)
                } else {
                    failure = Self.headline(for: error)
                    let rateLimited: Bool
                    if case GatitaError.http(429, _) = error { rateLimited = true } else { rateLimited = false }
                    // A rate limit is the server's rule, not a bug, so it gets no failure report either.
                    let report = rateLimited ? nil : self.recordFailure(kind: "reply", message: error.localizedDescription,
                                                                        details: ["model: \(self.model)", "project: \(self.projectRoot)"])
                    self.addErrorBubble(Self.headline(for: error), detail: Self.detail(for: error, report: report))
                    self.removeIfEmpty(replyID)
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
            // Gatita did not count this reply, so estimate it from the text.
            if let index = self.messages.firstIndex(where: { $0.id == replyID }), self.messages[index].usage == nil,
               !self.messages[index].content.isEmpty {
                self.messages[index].usage = TokenEstimate.usage(sentText: history.map(\.sentText),
                                                                 reply: self.messages[index].content)
                self.log.info("no token count from the server, so the reply was estimated")
            }
            self.updateReply(replyID) { $0.isStreaming = false; $0.respondedAt = Date() }
            self.retryAt = nil
            self.isSending = false
            self.sendTask = nil
            // A reply that changed memory says so, so a fact saved because of a page or a tool result is never unseen.
            if let reply = self.messages.first(where: { $0.id == replyID }),
               let note = MemoryStore.notice(reply.activities.compactMap { activity in
                   activity.result.map { (tool: activity.name, result: $0) }
               }) {
                self.messages.append(ChatMessage(role: "notice", content: note))
            }
            if !self.messages.isEmpty {
                self.saveCurrentChat()
                if let id = self.currentConversationID { self.requestTitle(forChat: id) }
            }
            self.reloadMemories()
            if let recorder, !recorder.checkpoint.files.isEmpty { self.undoableReplies.insert(replyID) }
            self.notifyOutcome(replyID: replyID, finished: finished, failure: failure)
        }
    }

    /// Sends a notification about how the reply ended: finished, a question, or a failure. A reply you stopped
    /// sends none. The notifier stays quiet while Gatita is the app in front.
    private func notifyOutcome(replyID: UUID, finished: Bool, failure: String?) {
        let chatID = currentConversationID
        let title = conversations.first { $0.id == chatID }?.title ?? ChatHistory.title(for: messages)
        if let question = pendingQuestion {
            notifier.post(Notifier.question(chatTitle: title, question: question), chatID: chatID)
        } else if finished, let reply = messages.first(where: { $0.id == replyID }) {
            notifier.post(Notifier.replyFinished(chatTitle: title, reply: reply.content), chatID: chatID)
        } else if let failure {
            notifier.post(Notifier.failed(chatTitle: title, reason: failure), chatID: chatID)
        }
    }

    /// One reply with no tools, used for writing text such as a pull request description.
    func oneShot(_ prompt: String) async throws -> String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ToolError("Add your Gatita API key in Settings first.") }
        return try await GatitaClient(apiKey: key, model: model)
            .send(messages: [ChatMessage(role: "user", content: prompt)])
    }

    /// Adds files dropped on the prompt box. A file Gatita cannot read is reported and left out. Files are read off
    /// the main thread, so a large PDF does not freeze the window.
    func attachDroppedFiles(_ urls: [URL]) {
        Task {
            for url in urls {
                do {
                    let file = try await Task.detached(priority: .userInitiated) { try DroppedFile.read(url) }.value
                    droppedFiles.append(file)
                    log.info("attached dropped file \(url.lastPathComponent)")
                } catch {
                    log.info("could not attach dropped file \(url.lastPathComponent): \(error.localizedDescription)")
                    errorMessage = error.localizedDescription
                }
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
        // A command waiting for an answer is denied, so the reply can end.
        answerCommand(.deny)
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

    /// Writes the chat on screen into the history, if it has a question or a reply.
    func saveCurrentChat() {
        guard ChatHistory.isWorthSaving(messages) else { return }
        let id = currentConversationID ?? UUID()
        currentConversationID = id
        // Saving again keeps the chat's title, pin, and folder.
        conversations = ChatHistory.updated(conversations, id: id, messages: messages, mode: sessionMode, at: Date())
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
        if case .waiting = event {} else { retryAt = nil }
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
        case .waiting(let seconds):
            retryAt = Date().addingTimeInterval(TimeInterval(seconds))
            analytics.count("rate_limited")
            log.info("rate limited, waiting \(seconds) s before sending again")
        case .text, .reasoning, .usage:
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
            case .question, .safetyStop, .waiting:
                break
            case .usage(let usage):
                reply.usage = reply.usage?.adding(usage) ?? usage
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
        notifier.prepare()
        sendTask = Task {
            var finished = false
            var failure: String?
            do {
                let answer = try await self.remoteMac.ask(prompt) { piece in
                    self.updateReply(replyID) { $0.content += piece }
                }
                self.updateReply(replyID) { $0.content = answer }
                finished = true
            } catch {
                failure = "Gatita could not reach your Mac."
                self.analytics.count("paired_device_unreachable")
                self.log.error("could not reach the paired device: \(error.localizedDescription)")
                self.messages.removeAll { $0.id == replyID && $0.content.isEmpty }
                self.addErrorBubble("Gatita could not reach your Mac.", detail: error.localizedDescription)
            }
            self.updateReply(replyID) { $0.isStreaming = false; $0.respondedAt = Date() }
            self.isSending = false
            self.sendTask = nil
            self.saveCurrentChat()
            self.notifyOutcome(replyID: replyID, finished: finished, failure: failure)
        }
    }

    /// The pairing code is kept in the Keychain. An empty code removes it.
    private func saveRemoteCode() {
        guard !Self.isTesting else { return }
        let code = remoteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if code.isEmpty {
            _ = KeychainStore.delete(account: "remote-code")
        } else {
            _ = KeychainStore.save(code, account: "remote-code")
        }
    }

    /// A reply with nothing in it (no text, thinking, or tool calls) is not left behind as an empty gap above an error.
    private func removeIfEmpty(_ id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        let reply = messages[index]
        if reply.content.isEmpty, reply.reasoning.isEmpty, reply.activities.isEmpty {
            messages.remove(at: index)
        }
    }

    /// Shows "Error: No internet access." once: an earlier copy of it is removed first.
    private func showNoInternet() {
        messages.removeAll { $0.role == "error" && $0.content == NoInternet.headline }
        addErrorBubble(NoInternet.headline, detail: NoInternet.detail)
    }

    /// Shows an error as a red message after the latest one. It is not sent back to Gatita.
    private func addErrorBubble(_ headline: String, detail: String? = nil) {
        messages.append(ChatMessage(role: "error", content: headline, errorText: detail))
    }

    /// The first line of an error bubble.
    private static func headline(for error: Error) -> String {
        if let gatita = error as? GatitaError, case .http(429, _) = gatita {
            return "Gatita's rate limit was reached."
        }
        if let gatita = error as? GatitaError, case .http(let status, _) = gatita {
            return "Gatita could not answer (HTTP \(status))."
        }
        if let gatita = error as? GatitaError, case .endedEarly = gatita {
            return "Gatita's reply ended early."
        }
        if let gatita = error as? GatitaError, case .toolRoundLimit = gatita {
            return "Gatita paused after many tool calls."
        }
        return "Gatita could not answer."
    }

    /// The detail under the headline. A "Reason:" line appears only when the server gave one.
    private static func detail(for error: Error, report: String?) -> String? {
        var lines: [String] = []
        if let gatita = error as? GatitaError, case .http(let status, let body) = gatita {
            if let reason = GatitaError.serverReason(in: body) {
                lines.append("Reason: \(reason)")
            }
            if status == 429 {
                lines.append("Gatita waited and tried again, but the limit held. Wait a minute, then send \"continue\".")
            }
        } else {
            lines.append(error.localizedDescription)
            if let gatita = error as? GatitaError {
                switch gatita {
                case .endedEarly, .toolRoundLimit: lines.append("Send \"continue\" to go on.")
                default: break
                }
            }
        }
        if let report {
            lines.append("Report saved: \(report)")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
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
                                       allowWrites: allowWrites, allowCommands: allowCommands, skillID: skillID, mode: mode, keepAwake: keepAwake, transcriptView: transcriptView, customInstructions: customInstructions,
                                       doubleCommandOpensPanel: doubleCommandOpensPanel,
                                       doubleCommandTakesScreenshot: doubleCommandTakesScreenshot,
                                       memoryEnabled: memoryEnabled,
                                       askBeforeCommands: askBeforeCommands,
                                       commandRules: commandRules),
                           to: SettingsStore.defaultFile)
    }

    private func persistAPIKey() {
        // The test host never changes the real key.
        guard !Self.isTesting else { return }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty {
            KeychainStore.delete(account: Self.keyAccount)
        } else {
            KeychainStore.save(key, account: Self.keyAccount)
        }
    }
}

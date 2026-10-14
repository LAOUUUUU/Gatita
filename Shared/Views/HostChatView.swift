//
//  HostChatView.swift
//  Gatita
//

import SwiftUI
import UniformTypeIdentifiers

/// The ⌘F bar over the chat: the words to find, which match is shown, next and previous, and close.
private struct FindBar: View {
    @Bindable var viewModel: ChatViewModel
    @FocusState private var focused: Bool

    var body: some View {
        let count = viewModel.findMatches.count
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Find in this chat", text: $viewModel.findQuery)
                .textFieldStyle(.plain)
                .frame(width: 180)
                .focused($focused)
                .onSubmit { viewModel.findStep(1) }
            Text(count > 0 ? "\(min(viewModel.findIndex, count - 1) + 1) of \(count)"
                 : viewModel.findQuery.isEmpty ? "" : "No matches")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 62, alignment: .trailing)
            Button { viewModel.findStep(-1) } label: { Image(systemName: "chevron.up") }
                .disabled(count == 0)
                .help("Previous match (⇧⌘G)")
            Button { viewModel.findStep(1) } label: { Image(systemName: "chevron.down") }
                .disabled(count == 0)
                .help("Next match (⌘G)")
            Button { viewModel.stopFinding() } label: { Image(systemName: "xmark") }
                .keyboardShortcut(.cancelAction)
                .help("Close (Escape)")
        }
        .buttonStyle(.plain)
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Capsule().fill(Theme.surface))
        .overlay(Capsule().stroke(Color.white.opacity(0.1)))
        .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
        .claimsEscape(true)
        .onAppear { focused = true }
        .onChange(of: viewModel.findFocusRequests) { _, _ in focused = true }
    }
}

/// A command Gatita wants to run, waiting for your answer: Deny (Escape), Always allow, or Allow once (Return).
private struct CommandApprovalCard: View {
    let request: CommandApproval.Request
    let project: String
    let answer: (CommandApproval.Decision) -> Void

    /// An MCP tool rather than a command, and its server and tool names.
    private var mcpTool: (server: String, tool: String)? {
        MCPConfig.split(request.rule)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: mcpTool == nil ? "terminal" : "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Theme.accent.opacity(0.15)))
                    Text(mcpTool == nil ? "Run this command?" : "Use this MCP tool?")
                        .font(.headline)
                }
                Text(request.command)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(mcpTool.map { "From the \($0.server) MCP server. It can do whatever that server allows, which may include changes outside Gatita." }
                     ?? "In \(project). It runs sandboxed, with no network, and writes only inside the project.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Deny") { answer(.deny) }
                        .buttonStyle(GatitaButtonStyle(.secondary))
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Always allow \(mcpTool?.tool ?? request.rule)") { answer(.allowAlways) }
                        .buttonStyle(GatitaButtonStyle(.secondary))
                        .help("Don't ask again for \(mcpTool?.tool ?? request.rule), with any arguments, in this project")
                    // No Return shortcut: someone typing in the prompt box as the card appears must not approve it.
                    Button("Allow once") { answer(.allowOnce) }
                        .buttonStyle(GatitaButtonStyle(.primary))
                }
            }
            .padding(20)
            .frame(maxWidth: 460, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(white: 0.1)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.1)))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
            .padding(24)
        }
        .claimsEscape(true)
    }
}

/// Escape stops a reply while one is on its way, unless a menu or a dialog is open (see `EscapeClaims`).
private struct StopReplyShortcut: View {
    let viewModel: ChatViewModel
    @Environment(EscapeClaims.self) private var escape: EscapeClaims?

    var body: some View {
        if viewModel.isSending, escape?.isClaimed != true {
            Button("Stop") { viewModel.stop() }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .allowsHitTesting(false)
        }
    }
}

/// The chat screen for a host device. The sidebar lists saved chats, or project files on the Mac.
/// The conversation and the prompt box sit on the right.
struct HostChatView: View {
    @Bindable var viewModel: ChatViewModel
    @State private var sidebarChoice: SidebarChoice = .chats
    @State private var search = ""
    @State private var showingPullRequest = false
    @State private var showingSettings = false
    @State private var showingShop = false
    @State private var showingActivity = true
    /// The chat list, shown as a sheet on iPhone and iPad. The chat is the first screen.
    @State private var showingChats = false
    @State private var promptPositions: [UUID: CGFloat] = [:]
    @State private var scrollOffset: CGFloat = 0
    /// True when the chat is scrolled all the way down. The prompt rail then highlights the last prompt.
    @State private var atBottom = false
    /// Names of the devices connected to this Mac. Shown at the top of the chat screen.
    var connectedDevices: [String] = []
    /// The Gatita dialog on screen, and what its confirm button does.
    @State private var dialog: GatitaDialogSpec?
    @State private var dialogAction: DialogAction?
    /// What is typed in a dialog: a chat's new title, or a new folder's name.
    @State private var dialogText = ""
    /// Folders folded shut in the sidebar.
    @State private var collapsedFolders: Set<String> = []
    /// The chat being exported, as Markdown.
    @State private var exporting: MarkdownFile?
    /// The dialogs and menus open here, which take Escape from the Stop shortcut.
    @State private var escape = EscapeClaims()

    private enum DialogAction {
        case rename(UUID)
        case newFolder(UUID)
        case forceUndo(UUID)
        case deleteAll
    }

    private enum SidebarChoice: String, CaseIterable, Identifiable {
        case chats = "Chats"
        case files = "Files"

        var id: String { rawValue }
    }

    private struct Starter: Identifiable {
        let id: String
        let title: String
        let icon: String
        let prompt: String
    }

    private static let codeStarters: [Starter] = [
        Starter(id: "project", title: "Explain this project", icon: "folder",
                prompt: "Explain how this project is organized. Start with list_files."),
        Starter(id: "changes", title: "Review my changes", icon: "doc.text.magnifyingglass",
                prompt: "Review my uncommitted changes. Start with git_status and git_diff."),
        Starter(id: "tests", title: "Suggest tests", icon: "checkmark.seal",
                prompt: "Find the code with the most logic and suggest tests for it."),
    ]

    /// Regular chat, with no project behind it.
    private static let chatStarters: [Starter] = [
        Starter(id: "research", title: "Research brief", icon: "magnifyingglass",
                prompt: "Write a short research brief on: "),
        Starter(id: "compare", title: "Compare sources", icon: "arrow.triangle.branch",
                prompt: "Compare these sources and say where they disagree: "),
        Starter(id: "draft", title: "Draft a message", icon: "pencil",
                prompt: "Help me draft a message that "),
    ]

    /// The Files list and the project actions belong to Code. In Chat, the sidebar shows only chats.
    private var showsFiles: Bool {
        sidebarChoice == .files && viewModel.mode == .code
    }

    var body: some View {
        layout
            .gatitaMenuHost()
            .overlay {
                if let request = viewModel.pendingCommand {
                    CommandApprovalCard(request: request,
                                        project: URL(fileURLWithPath: viewModel.projectRoot).lastPathComponent,
                                        answer: viewModel.answerCommand)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.15), value: viewModel.pendingCommand)
            .onChange(of: viewModel.undoConflict) { _, conflict in
                guard let conflict else { return }
                askForceUndo(conflict)
                viewModel.undoConflict = nil
            }
            .gatitaDialog($dialog, onConfirm: confirmDialog) {
                if let placeholder = dialogFieldPlaceholder {
                    TextField(placeholder, text: $dialogText)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .fileExporter(isPresented: Binding(get: { exporting != nil }, set: { if !$0 { exporting = nil } }),
                          document: exporting, contentType: MarkdownFile.type,
                          defaultFilename: exporting?.fileName) { result in
                if case .failure(let error) = result {
                    viewModel.errorMessage = "Could not export the chat: \(error.localizedDescription)"
                }
                exporting = nil
            }
            .environment(escape)
    }

    private func confirmDialog() {
        switch dialogAction {
        case .rename(let id): viewModel.renameChat(id, to: dialogText)
        case .newFolder(let id): viewModel.moveChat(id, toFolder: dialogText)
        case .forceUndo(let id): viewModel.undoChanges(id, force: true)
        case .deleteAll: viewModel.deleteAllChats(in: viewModel.mode)
        case nil: break
        }
        dialogAction = nil
    }

    /// The text field a dialog shows, if it has one.
    private var dialogFieldPlaceholder: String? {
        switch dialogAction {
        case .rename: "Title"
        case .newFolder: "Folder name, such as School"
        default: nil
        }
    }

    private func askForceUndo(_ conflict: ChatViewModel.UndoConflict) {
        dialogAction = .forceUndo(conflict.replyID)
        let names = conflict.files.joined(separator: ", ")
        dialog = GatitaDialogSpec(icon: "arrow.uturn.backward", title: "Undo anyway?",
                                  message: "\(names) changed after this reply. Undoing puts every file back as it was before the reply, so those later changes are lost.",
                                  confirm: "Undo anyway", role: .destructive)
    }

    private func askNewFolder(for chat: Conversation) {
        dialogText = ""
        dialogAction = .newFolder(chat.id)
        dialog = GatitaDialogSpec(icon: "folder.badge.plus", title: "New folder", message: "\(chat.title) goes in it.",
                                  confirm: "Create", closesOnOutsideTap: false)
    }

    private func askRename(_ chat: Conversation) {
        dialogText = chat.title
        dialogAction = .rename(chat.id)
        dialog = GatitaDialogSpec(icon: "pencil", title: "Rename chat", confirm: "Rename", closesOnOutsideTap: false)
    }

    private func askDeleteAll() {
        let count = viewModel.conversations(in: viewModel.mode).count
        dialogAction = .deleteAll
        dialog = GatitaDialogSpec(icon: "trash", title: "Delete all \(count) chats in \(viewModel.mode.displayName)?",
                                  message: "They are removed from this device for good. Chats in other modes stay.",
                                  confirm: "Delete all", role: .destructive)
    }

    private func export(_ chat: Conversation) {
        guard let file = viewModel.exportChat(chat.id) else { return }
        exporting = MarkdownFile(text: file.text, fileName: file.fileName)
    }

    @ViewBuilder
    private var layout: some View {
        #if os(macOS)
        MacChatLayout(viewModel: viewModel, showingActivity: $showingActivity, showingSettings: $showingSettings,
                      showingShop: $showingShop) { sidebar } detail: { detail }
        #else
        TouchChatLayout(viewModel: viewModel, showingChats: $showingChats) { sidebar } detail: { detail }
        #endif
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            #if os(macOS)
            HStack {
                Spacer()
                ModeSwitch(viewModel: viewModel)
            }
            #endif
            HStack(spacing: 8) {
                Image("GatitaLogo")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .foregroundStyle(.white)
                Text("Gatita Ask")
                    .font(.headline)
                #if os(macOS)
                Spacer()
                if viewModel.mode == .code {
                    sidebarIcon("folder", help: "Project files") {
                        sidebarChoice = sidebarChoice == .files ? .chats : .files
                    }
                }
                sidebarIcon("bag", help: "Shop") {
                    showingShop = true
                }
                #endif
            }

            Button {
                viewModel.newChat()
                showingChats = false
            } label: {
                Label("New chat", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.large)

            TextField("Search chats", text: $search)
                .textFieldStyle(.roundedBorder)

            HStack {
                Text(showsFiles ? "Files" : "Chats")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !showsFiles, !viewModel.conversations(in: viewModel.mode).isEmpty {
                    GatitaMenuButton(id: "chats-more", items: {
                        [GatitaMenuItem(title: "Delete all chats…", icon: "trash", isDestructive: true, action: askDeleteAll)]
                    }) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 18)
                            .contentShape(Rectangle())
                    }
                    .help("More")
                }
            }
            if showsFiles {
                filesList
            } else {
                chatList
            }
            #if os(macOS)
            profileRow
            #endif
        }
        .padding(12)
        .background(Theme.background.ignoresSafeArea())
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
    }

    /// A small icon button at the top of the sidebar.
    private func sidebarIcon(_ name: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// The account row at the bottom of the sidebar. It opens Settings.
    private var profileRow: some View {
        let name = NSFullUserName().components(separatedBy: " ").first ?? "Gatita"
        return Button {
            showingSettings = true
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(Theme.surface)
                    .frame(width: 30, height: 30)
                    .overlay(Text(String(name.prefix(1))).font(.callout.weight(.semibold)))
                VStack(alignment: .leading, spacing: 0) {
                    Text(name.isEmpty ? "Gatita" : name)
                        .font(.callout.weight(.medium))
                    Text("Settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface.opacity(0.5)))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var filesList: some View {
        #if os(macOS)
        ProjectFilesView(tools: viewModel.projectTools)
        #else
        EmptyView()
        #endif
    }

    private var chatList: some View {
        let chats = viewModel.conversations(in: viewModel.mode)
        let sections = ChatSidebar.sections(chats, search: search)
        let folders = ChatSidebar.folders(chats)

        return List(selection: selectionBinding) {
            ForEach(sections) { section in
                if section.kind == .folder {
                    Section(isExpanded: folderBinding(section.title)) {
                        ForEach(section.chats) { chatRow($0, folders: folders) }
                    } header: {
                        Label(section.title, systemImage: "folder")
                    }
                } else {
                    Section {
                        ForEach(section.chats) { chatRow($0, folders: folders) }
                    } header: {
                        // Without pins or folders, the list looks as it always did.
                        if sections.count > 1 || section.kind == .pinned {
                            Label(section.title, systemImage: section.kind == .pinned ? "pin" : "bubble.left.and.bubble.right")
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .overlay {
            if sections.isEmpty {
                Text("No saved chats yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func folderBinding(_ name: String) -> Binding<Bool> {
        Binding(get: { !collapsedFolders.contains(name) },
                set: { open in
                    if open { collapsedFolders.remove(name) } else { collapsedFolders.insert(name) }
                })
    }

    private func chatRow(_ chat: Conversation, folders: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(chat.title)
                .lineLimit(1)
            // While searching, the words around the match instead of the latest reply.
            Text(search.isEmpty ? chat.preview : ChatSearch.snippet(in: chat.messages, query: search) ?? chat.preview)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .tag(chat.id)
        .contextMenu {
            Button(chat.pinned == true ? "Unpin" : "Pin", systemImage: chat.pinned == true ? "pin.slash" : "pin") {
                viewModel.togglePinChat(chat.id)
            }
            Menu("Move to Folder", systemImage: "folder") {
                ForEach(folders.filter { $0 != chat.folder }, id: \.self) { folder in
                    Button(folder) { viewModel.moveChat(chat.id, toFolder: folder) }
                }
                if !folders.isEmpty { Divider() }
                Button("New Folder…", systemImage: "folder.badge.plus") { askNewFolder(for: chat) }
                if chat.folder != nil {
                    Button("Take Out of Folder") { viewModel.moveChat(chat.id, toFolder: nil) }
                }
            }
            Divider()
            Button("Rename…", systemImage: "pencil") { askRename(chat) }
            Button("Export as Markdown…", systemImage: "square.and.arrow.up") { export(chat) }
            Divider()
            Button("Delete chat", systemImage: "trash", role: .destructive) {
                viewModel.deleteChat(chat.id)
            }
        }
    }

    private var selectionBinding: Binding<UUID?> {
        Binding(
            get: { viewModel.currentConversationID },
            set: { id in
                if let id {
                    viewModel.openChat(id)
                    showingChats = false
                }
            })
    }

    /// Whether this chat reaches a device: the paired Mac in the PC tab, or a device connected to this Mac.
    private var connectionLine: (text: String, connected: Bool)? {
        if viewModel.mode == .remote {
            let name = viewModel.remoteMac.connectedName
            return (RemoteStatus.line(connectedName: name), name != nil)
        }
        guard let text = RemoteStatus.hostLine(names: connectedDevices) else { return nil }
        return (text, true)
    }

    /// Shown at the top of the chat while the device has no network. The PC tab can still reach a Mac nearby.
    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 13, weight: .semibold))
            Text("No internet access")
                .font(.callout.weight(.semibold))
            Text(viewModel.mode == .remote
                 ? "Your paired Mac can still answer over the local network."
                 : "Gatita can't answer until you're back online.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .foregroundStyle(.red)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.red.opacity(0.12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: No internet access")
    }

    private func connectionBanner(_ line: (text: String, connected: Bool)) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(line.connected ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(line.text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(spacing: 0) {
            if !viewModel.connectivity.isOnline {
                offlineBanner
            }
            if let line = connectionLine {
                connectionBanner(line)
            }
            if viewModel.messages.isEmpty {
                starterScreen
            } else {
                conversation
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            if let problem = viewModel.voice.problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            if let retryAt = viewModel.retryAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Label(RateLimit.note(until: retryAt, now: context.date), systemImage: "hourglass")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
            }

            HostInputBar(viewModel: viewModel)
                .frame(maxWidth: 800)
                .frame(maxWidth: .infinity)
                .background { StopReplyShortcut(viewModel: viewModel) }

            Text("Gatita may create biased or incorrect information. Verify critical facts.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
        }
        #if os(macOS)
        .overlay(alignment: .topTrailing) {
            MacChatToolbar(viewModel: viewModel, showingActivity: $showingActivity, showingPullRequest: $showingPullRequest)
        }
        #endif
        #if os(macOS)
        .sheet(isPresented: $showingPullRequest) {
            pullRequestSheet
        }
        #endif
    }

    private var starterScreen: some View {
        VStack(spacing: 20) {
            Spacer()
            Image("GatitaLogo")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .foregroundStyle(.white)
            Text(greeting)
                .font(.title2)
                .foregroundStyle(.white.opacity(0.85))
            if viewModel.mode != .remote {
                starterChips
            }
            Spacer()
        }
        .padding()
    }

    /// The starter prompts: a row on the Mac, and a column on iPhone and iPad, so every prompt stays on screen.
    @ViewBuilder
    private var starterChips: some View {
        let items = viewModel.mode == .code ? Self.codeStarters : Self.chatStarters
        #if os(macOS)
        HStack(spacing: 10) {
            ForEach(items) { item in
                starterButton(item)
            }
        }
        #else
        VStack(spacing: 8) {
            ForEach(items) { item in
                starterButton(item)
            }
        }
        #endif
    }

    private func starterButton(_ item: Starter) -> some View {
        Button {
            viewModel.draft = item.prompt
        } label: {
            Label(item.title, systemImage: item.icon)
        }
        .buttonStyle(PillButtonStyle())
    }

    /// Brings the current ⌘F match into the middle of the view.
    private func scrollToMatch(_ proxy: ScrollViewProxy) {
        let matches = viewModel.findMatches
        guard !matches.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            proxy.scrollTo(matches[min(viewModel.findIndex, matches.count - 1)].messageID, anchor: .center)
        }
    }

    private var promptCount: Int {
        viewModel.messages.filter { $0.role == "user" }.count
    }

    /// A centred column of messages, with a rail of prompt lines in the middle of the right edge.
    /// The accent line is the prompt at the top of the view. Click a line to jump to its prompt.
    private var conversation: some View {
        ScrollViewReader { proxy in
            HStack(spacing: 10) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message, transcriptView: viewModel.transcriptView,
                                          onAction: { viewModel.performAction($0, on: message.id) },
                                          isSpeaking: viewModel.speaker.speakingID == message.id,
                                          isBusy: viewModel.isSending,
                                          canUndo: viewModel.undoableReplies.contains(message.id))
                                .id(message.id)
                                .background(promptPosition(for: message))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 28)
                    .coordinateSpace(name: "chatContent")
                    .environment(\.findHighlight, viewModel.isFinding ? viewModel.findQuery : "")
                }
                .scrollIndicators(.never)
                .frame(maxWidth: 760)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y
                } action: { _, offset in
                    scrollOffset = offset
                }
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    // Within a few points of the end counts as the bottom.
                    geometry.contentOffset.y >= geometry.contentSize.height - geometry.containerSize.height - 8
                } action: { _, bottom in
                    atBottom = bottom
                }
                .onPreferenceChange(PromptPositionKey.self) { promptPositions = $0 }
                .overlay(alignment: .bottom) {
                    if !atBottom, let last = viewModel.messages.last {
                        Button {
                            withAnimation(.easeInOut(duration: 0.4)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        } label: {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(Theme.surface))
                                .overlay(Circle().stroke(Color.white.opacity(0.12)))
                                .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 12)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                        .help("Jump to the latest message")
                    }
                }
                .animation(.easeOut(duration: 0.2), value: atBottom)
                .overlay(alignment: .top) {
                    if viewModel.isFinding {
                        // Below the row of buttons at the top of the chat, so it never covers them.
                        FindBar(viewModel: viewModel)
                            .padding(.top, 50)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.easeOut(duration: 0.15), value: viewModel.isFinding)
                .onChange(of: viewModel.findIndex) { _, _ in scrollToMatch(proxy) }
                .onChange(of: viewModel.findQuery) { _, _ in scrollToMatch(proxy) }
                .onChange(of: promptCount) { _, _ in
                    // A new prompt scrolls to the top of the view, and the answer grows below it.
                    if let last = viewModel.messages.last(where: { $0.role == "user" }) {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .top)
                        }
                    }
                }

                promptRail(proxy: proxy)
            }
            .frame(maxWidth: 800)
            .frame(maxWidth: .infinity)
        }
    }

    /// Reports where a prompt sits in the conversation, so the rail can tell which prompt is on screen.
    private func promptPosition(for message: ChatMessage) -> some View {
        GeometryReader { geometry in
            Color.clear.preference(
                key: PromptPositionKey.self,
                value: message.role == "user" ? [message.id: geometry.frame(in: .named("chatContent")).minY] : [:])
        }
    }

    /// One short line per prompt, stacked in the middle of the right edge. Each line is a button with a
    /// larger hit area than the line, and the accent line moves with an animation as you scroll.
    private func promptRail(proxy: ScrollViewProxy) -> some View {
        let prompts = viewModel.messages.filter { $0.role == "user" }
        let current = currentPrompt(among: prompts)
        return VStack(spacing: 4) {
            ForEach(prompts) { prompt in
                let isCurrent = prompt.id == current
                Button {
                    jump(to: prompt.id, proxy: proxy)
                } label: {
                    Capsule()
                        .fill(isCurrent ? Theme.accent : Color.white.opacity(0.3))
                        .frame(width: isCurrent ? 22 : 16, height: 2)
                        .frame(width: 26, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(String(prompt.content.prefix(80)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: current)
        .frame(width: 26)
        .frame(maxHeight: .infinity)
    }

    /// Scrolls the conversation to a prompt, with an animation.
    private func jump(to id: UUID, proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.45)) {
            proxy.scrollTo(id, anchor: .top)
        }
    }

    /// The last prompt that has reached the top of the view, or the first prompt before any has.
    private func currentPrompt(among prompts: [ChatMessage]) -> UUID? {
        PromptRail.current(order: prompts.map(\.id), positions: promptPositions, offset: scrollOffset, atBottom: atBottom)
    }

    private struct PromptPositionKey: PreferenceKey {
        static var defaultValue: [UUID: CGFloat] = [:]

        static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
            value.merge(nextValue()) { _, new in new }
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "morning" : (hour < 18 ? "afternoon" : "evening")
        let name = NSFullUserName().components(separatedBy: " ").first ?? ""
        return name.isEmpty ? "Good \(part)" : "Good \(part), \(name)"
    }

    #if os(macOS)
    @ViewBuilder
    private var pullRequestSheet: some View {
        if let root = viewModel.projectTools?.root {
            PullRequestView(folder: root, analytics: viewModel.analytics, log: viewModel.log,
                            draft: { prompt in try await viewModel.oneShot(prompt) })
                .presentationBackground(Theme.background)
        } else {
            Text("Set a project folder in Settings first.")
                .padding()
        }
    }
    #endif
}

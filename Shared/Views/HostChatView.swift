//
//  HostChatView.swift
//  Gatita
//

import SwiftUI

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
    /// Names of the devices connected to this Mac. Shown at the top of the chat screen.
    var connectedDevices: [String] = []

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
        #if os(macOS)
        // The Mac uses two plain columns. A NavigationSplitView sidebar floats as a rounded panel, and it keeps a toolbar strip.
        HStack(spacing: 0) {
            sidebar
                .frame(width: 260)
                .frame(maxHeight: .infinity)
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 1)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if viewModel.mode == .code && showingActivity {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 1)
                ActivityPanel(viewModel: viewModel) {
                    showingActivity = false
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("")
        .sheet(isPresented: $showingSettings) {
            HostSettingsView(viewModel: viewModel)
                .frame(width: 560, height: 680)
                .presentationBackground(Theme.background)
        }
        .sheet(isPresented: $showingShop) {
            ShopView(viewModel: viewModel)
                .frame(width: 620, height: 680)
                .presentationBackground(Theme.background)
        }
        #else
        NavigationStack {
            detail
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button {
                            showingChats = true
                        } label: {
                            Image(systemName: "sidebar.left")
                        }
                        .accessibilityLabel("Chats")
                    }
                    ToolbarItemGroup {
                        NotificationBadge(viewModel: viewModel)
                    }
                }
        }
        .sheet(isPresented: $showingChats) {
            NavigationStack {
                sidebar
            }
        }
        .background(Theme.background)
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

            Text(showsFiles ? "Files" : "Chats")
                .font(.caption)
                .foregroundStyle(.secondary)
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
            .sorted { $0.updatedAt > $1.updatedAt }
            .filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }

        return List(selection: selectionBinding) {
            ForEach(chats) { chat in
                VStack(alignment: .leading, spacing: 2) {
                    Text(chat.title)
                        .lineLimit(1)
                    Text(chat.preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .tag(chat.id)
                .contextMenu {
                    Button("Delete chat", role: .destructive) {
                        viewModel.deleteChat(chat.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .overlay {
            if chats.isEmpty {
                Text("No saved chats yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

            HostInputBar(viewModel: viewModel)
                .frame(maxWidth: 800)
                .frame(maxWidth: .infinity)

            Text("Gatita may create biased or incorrect information. Verify critical facts.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
        }
        #if os(macOS)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 10) {
                if viewModel.mode == .code {
                    Button {
                        showingActivity.toggle()
                    } label: {
                        Image(systemName: "sidebar.trailing")
                            .font(.system(size: 14))
                            .foregroundStyle(showingActivity ? Theme.accent : .secondary)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .help("Activity")
                }
                NotificationBadge(viewModel: viewModel)
                if viewModel.mode == .code {
                    Button {
                        showingPullRequest = true
                    } label: {
                        Image(systemName: "arrow.triangle.pull")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .help("Create a pull request")
                }
            }
            .padding(.top, 12)
            .padding(.trailing, 16)
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
                            MessageBubble(message: message)
                                .id(message.id)
                                .background(promptPosition(for: message))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 28)
                    .coordinateSpace(name: "chatContent")
                }
                .scrollIndicators(.never)
                .frame(maxWidth: 760)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y
                } action: { _, offset in
                    scrollOffset = offset
                }
                .onPreferenceChange(PromptPositionKey.self) { promptPositions = $0 }
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
        let reached = prompts.last(where: { (promptPositions[$0.id] ?? 0) <= scrollOffset + 40 })
        return (reached ?? prompts.first)?.id
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

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
    @State private var promptPositions: [UUID: CGFloat] = [:]
    @State private var scrollOffset: CGFloat = 0

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

    private static let starters: [Starter] = [
        Starter(id: "project", title: "Explain this project", icon: "folder",
                prompt: "Explain how this project is organized. Start with list_files."),
        Starter(id: "changes", title: "Review my changes", icon: "doc.text.magnifyingglass",
                prompt: "Review my uncommitted changes. Start with git_status and git_diff."),
        Starter(id: "tests", title: "Suggest tests", icon: "checkmark.seal",
                prompt: "Find the code with the most logic and suggest tests for it."),
    ]

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .background(Theme.background)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image("GatitaLogo")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .foregroundStyle(.white)
                Text("Gatita Ask")
                    .font(.headline)
            }

            Button {
                viewModel.newChat()
            } label: {
                Label("New chat", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.large)

            TextField("Search chats", text: $search)
                .textFieldStyle(.roundedBorder)

            #if os(macOS)
            Picker("Sidebar", selection: $sidebarChoice) {
                ForEach(SidebarChoice.allCases) { choice in
                    Text(choice.rawValue).tag(choice)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .tint(Theme.accent)
            #endif

            if sidebarChoice == .files {
                filesList
            } else {
                chatList
            }
        }
        .padding(12)
        .background(Theme.background)
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
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
        let chats = viewModel.conversations
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
                if let id { viewModel.openChat(id) }
            })
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(spacing: 0) {
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
        .toolbar {
            ToolbarItemGroup {
                NotificationBadge(viewModel: viewModel)
                #if os(macOS)
                Button {
                    showingPullRequest = true
                } label: {
                    Label("Create PR", systemImage: "arrow.triangle.pull")
                }
                #endif
            }
        }
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
            HStack(spacing: 10) {
                ForEach(Self.starters) { item in
                    Button {
                        viewModel.draft = item.prompt
                    } label: {
                        Label(item.title, systemImage: item.icon)
                    }
                    .buttonStyle(.bordered)
                    .clipShape(Capsule())
                }
            }
            Spacer()
        }
        .padding()
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

    /// One short line per prompt, stacked in the middle of the right edge.
    private func promptRail(proxy: ScrollViewProxy) -> some View {
        let prompts = viewModel.messages.filter { $0.role == "user" }
        let current = currentPrompt(among: prompts)
        return VStack(spacing: 10) {
            ForEach(prompts) { prompt in
                Capsule()
                    .fill(prompt.id == current ? Theme.accent : Color.white.opacity(0.3))
                    .frame(width: 16, height: 2)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation {
                            proxy.scrollTo(prompt.id, anchor: .top)
                        }
                    }
            }
        }
        .frame(width: 22)
        .frame(maxHeight: .infinity)
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

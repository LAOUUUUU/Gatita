//
//  ProjectBar.swift
//  Gatita
//

#if os(macOS)
import AppKit
import SwiftUI

/// The bar above the prompt box in Code mode: where the project runs, its folder, and the git worktree it is in.
/// A folder under git selects its own worktree on its own. The branch menu switches to another worktree.
/// The bar uses the full labels when the window is wide, and icons with shorter names when it is narrow.
struct ProjectBar: View {
    @Bindable var viewModel: ChatViewModel
    @State private var repo = RepoState.notARepo
    @State private var roblox: RobloxProject?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            bar(compact: false)
            bar(compact: true)
        }
        .task(id: viewModel.projectRoot) {
            repo = await loadRepo()
        }
        .task(id: viewModel.projectRoot) {
            roblox = nil
            let found = await loadRoblox()
            // A folder picked meanwhile cancels this task, and its late answer must not replace the newer one.
            if !Task.isCancelled { roblox = found }
        }
    }

    private func bar(compact: Bool) -> some View {
        HStack(spacing: 6) {
            pill(compact ? nil : "Local", icon: "laptopcomputer")

            Button(action: chooseFolder) {
                pill(Self.shortened(folderName, to: compact ? 12 : 24), icon: "folder")
            }
            .buttonStyle(.plain)
            .help("Choose the project folder")

            if repo.isRepo {
                branchMenu(compact: compact)
            }

            if let roblox {
                pill(compact ? nil : "Roblox", icon: "gamecontroller")
                    .help(roblox.summary(studioConnected: Self.studioIsConnected(viewModel.mcp.status)))
            }

            ForEach(runningTasks.prefix(3)) { task in
                Button {
                    _ = viewModel.tasks.stopBackground(task.id)
                } label: {
                    pill(Self.shortened(task.command, to: compact ? 10 : 24), icon: "stop.circle.fill", tint: Theme.accent)
                }
                .buttonStyle(.plain)
                .help("Stop this background task")
            }

            Button(action: chooseFolder) {
                pill(nil, icon: "folder.badge.plus")
            }
            .buttonStyle(.plain)
            .help("Choose a project folder")

            Spacer(minLength: 0)
        }
    }

    /// Whether an MCP server for Roblox Studio is connected. The user picks the server's name, so any connected
    /// server with "roblox" in its name counts.
    static func studioIsConnected(_ statuses: [String: MCPHub.Status]) -> Bool {
        statuses.contains { key, status in
            if case .connected = status { return key.contains("roblox") }
            return false
        }
    }

    /// Shortens a long name in the middle, so it fits in a chip of its own width. Names at or under the limit stay whole.
    static func shortened(_ text: String, to limit: Int) -> String {
        guard text.count > limit, limit > 1 else { return text }
        let keep = limit - 1
        let head = (keep + 1) / 2
        let tail = keep - head
        return String(text.prefix(head)) + "…" + String(text.suffix(tail))
    }

    /// Background commands that are still running. Each one gets a stop chip.
    private var runningTasks: [BackgroundTask] {
        viewModel.tasks.background.filter { $0.status == .running }
    }

    private var folderName: String {
        viewModel.projectRoot.isEmpty ? "No folder" : URL(fileURLWithPath: viewModel.projectRoot).lastPathComponent
    }

    private func branchMenu(compact: Bool) -> some View {
        GatitaMenuButton(id: "worktrees", title: "Worktrees", alignTrailing: false, width: 300, items: {
            repo.worktrees.map { tree in
                GatitaMenuItem(title: tree.branch ?? "detached HEAD", subtitle: tree.name, icon: "arrow.triangle.branch",
                               isSelected: tree.id == repo.current?.id) { viewModel.projectRoot = tree.path }
            }
        }) {
            pill(Self.shortened(repo.current?.branch ?? "detached HEAD", to: compact ? 10 : 20), icon: "arrow.triangle.branch")
        }
        .fixedSize()
        .help("Switch worktree")
    }

    /// One chip, 30 points tall like the prompt box's controls, with a rounded surface and secondary text.
    private func pill(_ title: String?, icon: String, tint: Color = .secondary) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(tint)
            if let title {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface.opacity(0.7)))
    }

    private func loadRepo() async -> RepoState {
        guard !viewModel.projectRoot.isEmpty else { return .notARepo }
        return await RepoStateLoader.load(for: URL(fileURLWithPath: viewModel.projectRoot))
    }

    private func loadRoblox() async -> RobloxProject? {
        guard !viewModel.projectRoot.isEmpty else { return nil }
        return await RobloxProject.load(in: URL(fileURLWithPath: viewModel.projectRoot))
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.projectRoot = url.path
        }
    }
}
#endif

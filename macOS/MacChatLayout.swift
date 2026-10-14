//
//  MacChatLayout.swift
//  Gatita
//

#if os(macOS)
import SwiftUI

/// The Mac chat window: two plain columns, the chats and the chat, with the Activity panel in Code mode, and the
/// Settings and Shop sheets. A NavigationSplitView sidebar would float as a rounded panel and keep a toolbar strip.
struct MacChatLayout<Sidebar: View, Detail: View>: View {
    let viewModel: ChatViewModel
    @Binding var showingActivity: Bool
    @Binding var showingSettings: Bool
    @Binding var showingShop: Bool
    @ViewBuilder let sidebar: () -> Sidebar
    @ViewBuilder let detail: () -> Detail

    var body: some View {
        HStack(spacing: 0) {
            sidebar()
                .frame(width: 260)
                .frame(maxHeight: .infinity)
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 1)
            detail()
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
            ShopView(viewModel: viewModel, onClose: { showingShop = false })
                .frame(width: 620, height: 680)
                .presentationBackground(Theme.background)
        }
    }
}

/// The buttons at the top right of the Mac chat: Activity and Create a pull request in Code mode, the transcript
/// view, and notifications.
struct MacChatToolbar: View {
    let viewModel: ChatViewModel
    @Binding var showingActivity: Bool
    @Binding var showingPullRequest: Bool

    var body: some View {
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
            GatitaMenuButton(id: "transcript", title: "Transcript view", items: {
                TranscriptView.allCases.map { view in
                    GatitaMenuItem(title: view.title, subtitle: view.summary,
                                   isSelected: viewModel.transcriptView == view) { viewModel.transcriptView = view }
                }
            }) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .help("Transcript view")
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
}
#endif

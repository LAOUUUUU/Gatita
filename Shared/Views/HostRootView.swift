//
//  HostRootView.swift
//  Gatita
//

import SwiftUI

#if os(iOS) || os(macOS) || os(visionOS)
/// The host device's screens: the chat, and a Settings tab for the key, model, project folder, and pairing.
/// The host session is attached to the settings, so a paired device can send chats to this one.
struct HostRootView: View {
    let viewModel: ChatViewModel
    let host: HostSession

    @State private var tab: HostTab = .chat

    private enum HostTab: Hashable { case chat, pc, settings, shop }

    var body: some View {
        Group {
            #if os(macOS)
            // On the Mac the chat is the whole window. Settings and Shop open from the sidebar.
            HostChatView(viewModel: viewModel, connectedDevices: host.connectedNames)
            #else
            TabView(selection: $tab) {
                HostChatView(viewModel: viewModel)
                    .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
                    .tag(HostTab.chat)

                // The PC tab sends its chats to the paired Mac. Its chats are kept apart from the Chat tab's.
                HostChatView(viewModel: viewModel)
                    .tabItem { Label("PC", systemImage: "desktopcomputer") }
                    .tag(HostTab.pc)

                HostSettingsView(viewModel: viewModel)
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(HostTab.settings)

                ShopView(viewModel: viewModel)
                    .tabItem { Label("Shop", systemImage: "bag") }
                    .tag(HostTab.shop)
            }
            .onChange(of: tab) { _, newTab in
                switch newTab {
                case .chat: viewModel.switchMode(to: .chat)
                case .pc: viewModel.switchMode(to: .remote)
                case .settings, .shop: break
                }
            }
            #endif
        }
        .onAppear { host.attach(viewModel) }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .background(Theme.background.ignoresSafeArea())
    }
}
#endif

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

    var body: some View {
        Group {
            #if os(macOS)
            // On the Mac the chat is the whole window. Settings and Shop open from the sidebar.
            HostChatView(viewModel: viewModel)
            #else
            TabView {
                HostChatView(viewModel: viewModel)
                    .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }

                HostSettingsView(viewModel: viewModel)
                    .tabItem { Label("Settings", systemImage: "gearshape") }

                ShopView(viewModel: viewModel)
                    .tabItem { Label("Shop", systemImage: "bag") }
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

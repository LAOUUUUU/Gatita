//
//  HostRootView.swift
//  Gatita
//

import SwiftUI

#if os(iOS) || os(macOS) || os(visionOS)
/// The host device's screens: the chat, and a Settings tab for the key, model, and project folder.
struct HostRootView: View {
    let viewModel: ChatViewModel

    var body: some View {
        #if os(macOS)
        // On the Mac the chat is the whole window. Settings and Shop open from the sidebar.
        HostChatView(viewModel: viewModel)
            .preferredColorScheme(.dark)
            .tint(Theme.accent)
            .background(Theme.background.ignoresSafeArea())
        #else
        TabView {
            HostChatView(viewModel: viewModel)
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }

            ScrollView {
                HostSettingsView(viewModel: viewModel)
                    .padding()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }

            ShopView(viewModel: viewModel)
                .tabItem { Label("Shop", systemImage: "bag") }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .background(Theme.background.ignoresSafeArea())
        #endif
    }
}
#endif

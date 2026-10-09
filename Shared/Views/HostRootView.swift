//
//  HostRootView.swift
//  Gatita
//

import SwiftUI

#if os(iOS) || os(macOS)
/// The host device's screens: the chat, and a Settings tab for the key, model, and project folder.
struct HostRootView: View {
    let viewModel: ChatViewModel

    var body: some View {
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
    }
}
#endif

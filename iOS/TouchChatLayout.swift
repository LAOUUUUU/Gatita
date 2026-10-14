//
//  TouchChatLayout.swift
//  Gatita
//

#if !os(macOS)
import SwiftUI

/// The chat on iPhone and iPad (and Vision Pro): the chat in a navigation stack, and the chats in a sheet opened
/// from the top-left button.
struct TouchChatLayout<Sidebar: View, Detail: View>: View {
    let viewModel: ChatViewModel
    @Binding var showingChats: Bool
    @ViewBuilder let sidebar: () -> Sidebar
    @ViewBuilder let detail: () -> Detail

    var body: some View {
        NavigationStack {
            detail()
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
                sidebar()
            }
            .gatitaMenuHost()
        }
        .background(Theme.background)
    }
}
#endif

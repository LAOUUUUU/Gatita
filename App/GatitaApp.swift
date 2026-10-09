//
//  GatitaApp.swift
//  Gatita
//
//  Created by LAOUUU on 2026-10-08.
//


import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct GatitaApp: App {
    #if os(iOS) || os(macOS) || os(visionOS)
    @State private var hostSession = HostSession()
    #elseif !os(watchOS)
    @State private var clientSession = ClientSession()
    #endif

    @State private var chatViewModel = ChatViewModel(
        apiKey: ProcessInfo.processInfo.environment["GATITA_API_KEY"] ?? "")

    init() {
        #if os(macOS)
        // Shows the cat in the Dock right away, without waiting for macOS to refresh its icon cache.
        NSApplication.shared.applicationIconImage = NSImage(named: "AppIconImage")
        #endif
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            #if os(watchOS)
            ChatView(viewModel: chatViewModel, clientSession: nil)
            #elseif os(iOS) || os(macOS) || os(visionOS)
            HostRootView(viewModel: chatViewModel)
            #else
            ChatView(viewModel: chatViewModel, clientSession: clientSession)
            #endif
        }
        .defaultSize(width: 1100, height: 720)

        #if os(macOS)
        MenuBarExtra {
            MenuBarMenu(viewModel: chatViewModel)
        } label: {
            MenuBarLabel(viewModel: chatViewModel)
        }
        #endif
    }
}

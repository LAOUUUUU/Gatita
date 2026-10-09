//
//  GatitaApp.swift
//  Gatita
//
//  Created by LAOUUU on 2026-10-08.
//


import SwiftUI

@main
struct GatitaApp: App {
    #if os(iOS) || os(macOS)
    @State private var hostSession = HostSession()
    #elseif !os(watchOS)
    @State private var clientSession = ClientSession()
    #endif

    @State private var chatViewModel = ChatViewModel(
        apiKey: ProcessInfo.processInfo.environment["GATITA_API_KEY"] ?? "")

    var body: some Scene {
        WindowGroup {
            #if os(watchOS)
            ChatView(viewModel: chatViewModel, clientSession: nil)
            #elseif os(iOS) || os(macOS)
            HostRootView(viewModel: chatViewModel)
            #else
            ChatView(viewModel: chatViewModel, clientSession: clientSession)
            #endif
        }
        .defaultSize(width: 720, height: 640)
    }
}

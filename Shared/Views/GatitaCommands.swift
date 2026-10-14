//
//  GatitaCommands.swift
//  Gatita
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

/// The Chat menu and its keyboard shortcuts. On iPad they work with a hardware keyboard.
struct GatitaCommands: Commands {
    let viewModel: ChatViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Chat") {
                viewModel.newChat()
                #if os(macOS)
                // New Chat takes New Window's place, so with the window closed it brings one back.
                if !NSApp.windows.contains(where: { $0.isVisible && !($0 is NSPanel) && $0.canBecomeMain }) {
                    openWindow(id: "main")
                }
                #endif
            }
            .keyboardShortcut("n")
        }
        CommandGroup(before: .textEditing) {
            Button("Find in Chat…") { viewModel.startFinding() }
                .keyboardShortcut("f")
            Button("Find Next") { viewModel.findStep(1) }
                .keyboardShortcut("g")
            Button("Find Previous") { viewModel.findStep(-1) }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            Divider()
        }
        CommandMenu("Chat") {
            Button("Stop Reply") { viewModel.stop() }
                .keyboardShortcut(".")
            Divider()
            Button("Copy Last Reply") { viewModel.copyLastReply() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button("Regenerate Last Reply") { viewModel.regenerateLastReply() }
                .keyboardShortcut("r")
            Button("Read Last Reply Aloud") { viewModel.readLastReplyAloud() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Divider()
            Button("Choose a Skill…") { viewModel.startSkillPicker() }
                .keyboardShortcut("k")
            #if os(macOS)
            Button("Quick Panel") { QuickPanelController.shared.toggle(viewModel) }
                .keyboardShortcut("g", modifiers: [.control, .command])
            #endif
        }
    }
}

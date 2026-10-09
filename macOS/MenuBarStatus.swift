//
//  MenuBarStatus.swift
//  Gatita
//

import SwiftUI
#if os(macOS)
import AppKit

/// The menu bar icon: the cat, with a count of finished replies and open questions.
struct MenuBarLabel: View {
    @Bindable var viewModel: ChatViewModel

    private var count: Int {
        viewModel.finishedReplies + (viewModel.pendingQuestion == nil ? 0 : 1)
    }

    var body: some View {
        HStack(spacing: 4) {
            Image("MenuBarIcon")
                .renderingMode(.template)
            if count > 0 {
                Text("\(count)")
                    .monospacedDigit()
            }
        }
    }
}

/// What the menu bar icon offers when clicked.
struct MenuBarMenu: View {
    @Bindable var viewModel: ChatViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let question = viewModel.pendingQuestion {
            Text("Gatita asks: \(question)")
            Button("Dismiss question") {
                viewModel.dismissQuestion()
            }
        }
        if viewModel.finishedReplies > 0 {
            Text("Finished replies: \(viewModel.finishedReplies)")
            Button("Clear finished") {
                viewModel.acknowledgeFinished()
            }
        }
        if viewModel.pendingQuestion == nil && viewModel.finishedReplies == 0 {
            Text("Nothing new")
        }
        Divider()
        Toggle("Keep the Mac awake", isOn: Binding(
            get: { viewModel.keepAwake },
            set: { viewModel.keepAwake = $0 }))
        Button("Open Gatita") {
            openWindow(id: "main")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        Button("Quit Gatita") {
            NSApplication.shared.terminate(nil)
        }
    }
}
#endif

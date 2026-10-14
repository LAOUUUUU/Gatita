//
//  MenuBarStatus.swift
//  Gatita
//

import SwiftUI
#if os(macOS)
import AppKit

/// The menu bar icon. It shows only while something long runs in the background (a command or a subagent) or
/// while the Mac is kept awake, with the number of running tasks. Finished replies are notifications instead.
struct MenuBarLabel: View {
    @Bindable var viewModel: ChatViewModel

    var body: some View {
        HStack(spacing: 4) {
            Image("MenuBarIcon")
                .renderingMode(.template)
            if viewModel.tasks.runningCount > 0 {
                Text("\(viewModel.tasks.runningCount)")
                    .monospacedDigit()
            }
        }
    }
}

/// What the menu bar icon offers when clicked: the running tasks, with a way to stop each command.
struct MenuBarMenu: View {
    @Bindable var viewModel: ChatViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let commands = viewModel.tasks.background.filter { $0.status == .running }
        let agents = viewModel.tasks.agents.filter { $0.status == .running }
        if commands.isEmpty && agents.isEmpty && viewModel.runningSchedules.isEmpty {
            Text("Nothing running in the background")
        }
        ForEach(commands) { task in
            Button("Stop \(task.command)") {
                _ = viewModel.tasks.stopBackground(task.id)
            }
        }
        ForEach(agents) { agent in
            Text("Subagent: \(String(agent.task.prefix(50)))")
        }
        ForEach(viewModel.scheduledPrompts.filter { viewModel.runningSchedules.contains($0.id) }) { prompt in
            Text("Scheduled: \(prompt.name)")
        }
        if let question = viewModel.pendingQuestion {
            Divider()
            Text("Gatita asks: \(question)")
        }
        Divider()
        Toggle("Keep the Mac awake", isOn: $viewModel.keepAwake)
            .toggleStyle(.checkbox)
        Button("Open Gatita") {
            openWindow(id: "main")
            NSApplication.shared.activate(ignoringOtherApps: false)
        }
        Button("Quit Gatita") {
            NSApp.sendAction(#selector(NSApplication.terminate(_:)), to: nil, from: nil)
        }
    }
}
#endif

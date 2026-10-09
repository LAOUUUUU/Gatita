//
//  ActivityPanel.swift
//  Gatita
//

#if os(macOS)
import SwiftUI

/// The panel on the right in Code mode: tool calls and commands, background tasks, subagents, and the files Gatita changed.
struct ActivityPanel: View {
    let viewModel: ChatViewModel
    let onClose: () -> Void

    private var activities: [ToolActivity] {
        viewModel.messages.flatMap(\.activities)
    }

    private var changes: [FileChange] {
        activities.compactMap(\.change)
    }

    private var tasks: TaskRegistry {
        viewModel.tasks
    }

    private var runningCount: Int {
        activities.filter { $0.status == .running }.count
            + tasks.background.filter { $0.status == .running }.count
            + tasks.agents.filter { $0.status == .running }.count
    }

    private var isEmpty: Bool {
        activities.isEmpty && tasks.background.isEmpty && tasks.agents.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if isEmpty {
                Spacer()
                Text("Commands, background tasks, and subagents show up here as Gatita works.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if !changes.isEmpty {
                            changedFiles
                        }
                        if !tasks.background.isEmpty {
                            backgroundTasks
                        }
                        if !tasks.agents.isEmpty {
                            subagents
                        }
                        if !activities.isEmpty {
                            toolCalls
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 340)
        .frame(maxHeight: .infinity)
        .background(Color.black.opacity(0.4))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Activity")
                .font(.headline)
            if runningCount > 0 {
                Text("\(runningCount) running")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.accent)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(0.06)))
            }
            .buttonStyle(.plain)
        }
    }

    private var changedFiles: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Changed files")
            ForEach(Array(changes.enumerated()), id: \.offset) { _, change in
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(Theme.accent)
                    Text(change.path)
                        .font(.callout.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text("+\(change.added)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.green)
                    Text("−\(change.removed)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.red)
                }
                .panelCard()
            }
        }
    }

    private var backgroundTasks: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Background tasks")
            ForEach(tasks.background.reversed()) { task in
                BackgroundCard(task: task) {
                    _ = tasks.stopBackground(task.id)
                }
            }
        }
    }

    private var subagents: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Subagents")
            ForEach(tasks.agents.reversed()) { agent in
                AgentCard(agent: agent)
            }
        }
    }

    private var toolCalls: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Tool calls")
            ForEach(activities.reversed()) { activity in
                ActivityCard(activity: activity)
            }
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}

/// A card in the panel: a rounded, softly edged box.
private extension View {
    func panelCard() -> some View {
        self
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06)))
            .contentShape(Rectangle())
    }
}

private extension ActivityStatus {
    var color: Color {
        switch self {
        case .running: Theme.accent
        case .done: .green
        case .failed: .red
        }
    }

    var label: String {
        switch self {
        case .running: "Running"
        case .done: "Done"
        case .failed: "Failed"
        }
    }
}

private extension BackgroundTask {
    var statusColor: Color {
        switch status {
        case .running: Theme.accent
        case .done: .green
        case .failed: .red
        case .stopped: .secondary
        }
    }

    var statusLabel: String {
        switch status {
        case .running: "Running"
        case .done: "Done"
        case .failed: "Failed"
        case .stopped: "Stopped"
        }
    }

    var runTime: TimeInterval? {
        finishedAt.map { $0.timeIntervalSince(startedAt) }
    }
}

private extension Subagent {
    var statusColor: Color {
        switch status {
        case .running: Theme.accent
        case .done: .green
        case .failed: .red
        }
    }

    var statusLabel: String {
        switch status {
        case .running: "Working"
        case .done: "Done"
        case .failed: "Failed"
        }
    }

    var runTime: TimeInterval? {
        finishedAt.map { $0.timeIntervalSince(startedAt) }
    }
}

/// A tool call: its icon, name, arguments, status, and time. Tap it to read the output.
private struct ActivityCard: View {
    let activity: ToolActivity
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                CardIcon(symbol: activity.symbol, color: activity.status.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.name)
                        .font(.callout.monospaced().weight(.medium))
                    Text(activity.arguments)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                StatusPill(label: activity.status.label, color: activity.status.color,
                           running: activity.status == .running, duration: activity.duration)
            }
            if expanded, let result = activity.result {
                CodeOutput(text: String(result.prefix(6000)))
            }
        }
        .panelCard()
        .onTapGesture {
            if activity.result != nil {
                expanded.toggle()
            }
        }
    }
}

/// A background command: its command, status, and output, with a stop button while it runs.
private struct BackgroundCard: View {
    let task: BackgroundTask
    let onStop: () -> Void
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                CardIcon(symbol: "terminal", color: task.statusColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.command)
                        .font(.callout.monospaced().weight(.medium))
                        .lineLimit(1)
                    Text(task.id)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                StatusPill(label: task.statusLabel, color: task.statusColor,
                           running: task.status == .running, duration: task.runTime)
                if task.status == .running {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.red)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.red.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                    .help("Stop this task")
                }
            }
            if expanded {
                CodeOutput(text: task.output.isEmpty ? "(no output yet)" : task.output)
            }
        }
        .panelCard()
        .onTapGesture {
            expanded.toggle()
        }
    }
}

/// A subagent: its task, status, and answer.
private struct AgentCard: View {
    let agent: Subagent
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                CardIcon(symbol: "person.2", color: agent.statusColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.task)
                        .font(.callout)
                        .lineLimit(2)
                    Text(agent.id)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                StatusPill(label: agent.statusLabel, color: agent.statusColor,
                           running: agent.status == .running, duration: agent.runTime)
            }
            if expanded, let result = agent.result {
                CodeOutput(text: String(result.prefix(6000)))
            }
        }
        .panelCard()
        .onTapGesture {
            if agent.result != nil {
                expanded.toggle()
            }
        }
    }
}

/// The icon at the start of a card, tinted by its status.
private struct CardIcon: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(color)
            .frame(width: 26, height: 26)
            .background(RoundedRectangle(cornerRadius: 7).fill(color.opacity(0.14)))
    }
}

/// Monospaced output in a black box, with a height limit and selectable text.
private struct CodeOutput: View {
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.caption.monospaced())
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxHeight: 220)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.06)))
    }
}

/// The status of a card: a spinner while it runs, then a dot, and its time.
private struct StatusPill: View {
    let label: String
    let color: Color
    let running: Bool
    let duration: TimeInterval?

    var body: some View {
        HStack(spacing: 5) {
            if running {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
            }
            Text(label)
                .font(.caption2.weight(.semibold))
            if let duration {
                Text(ActivityFormat.duration(duration))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.12)))
    }
}
#endif

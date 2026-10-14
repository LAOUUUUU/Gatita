//
//  ScheduledSettingsView.swift
//  Gatita
//

#if os(macOS)
import ServiceManagement
import SwiftUI

/// Settings, Scheduled: prompts Gatita runs on its own, each with its schedule, the next run, Run now, and an
/// on/off switch. They run while Gatita is open; "Open Gatita at login" keeps that true after a restart.
struct ScheduledSettingsView: View {
    @Bindable var viewModel: ChatViewModel
    @State private var dialog: GatitaDialogSpec?
    @State private var draft = Draft()
    @State private var loginItem = SMAppService.mainApp.status
    @State private var loginProblem: String?

    /// The prompt being made or changed in the dialog.
    struct Draft {
        var id: UUID?
        var name = ""
        var prompt = ""
        var mode: GatitaMode = .chat
        var repeats: Schedule.Repeat = .daily
        var time = Calendar.current.date(from: DateComponents(hour: 8, minute: 0)) ?? Date()
        var weekday = 2
    }

    var body: some View {
        List {
            Section {
                if viewModel.scheduledPrompts.isEmpty {
                    Text("Nothing scheduled yet. A scheduled prompt runs on its own, such as a morning news summary or a nightly check of the project.")
                        .foregroundStyle(.secondary)
                }
                ForEach(viewModel.scheduledPrompts) { prompt in
                    row(prompt)
                }
                Button {
                    edit(nil)
                } label: {
                    Label("New scheduled prompt", systemImage: "plus")
                }
                .buttonStyle(GatitaButtonStyle(.primary))
                .padding(.vertical, 4)
                SettingsNote(Text("Each run is saved as a chat in the Scheduled folder, and a notification says when it finishes. Runs happen while Gatita is open; a run missed while the Mac slept runs when it wakes, if it was due in the last 12 hours."))
            }

            Section {
                Toggle("Open Gatita at login", isOn: Binding(get: { loginItem == .enabled || loginItem == .requiresApproval },
                                                             set: setLoginItem))
                if loginItem == .requiresApproval {
                    HStack {
                        Text("macOS needs you to allow Gatita in Login Items.")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                            .buttonStyle(GatitaButtonStyle(.secondary))
                    }
                }
                if let loginProblem {
                    Text(loginProblem)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                SettingsNote(Text("So scheduled prompts keep running after the Mac restarts."))
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Scheduled")
        .onAppear { loginItem = SMAppService.mainApp.status }
        .gatitaDialog($dialog, onConfirm: save) { editor }
    }

    private func row(_ prompt: ScheduledPrompt) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(prompt.name)
                        .font(.callout.weight(.medium))
                    Text(prompt.mode.displayName)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Theme.surface))
                }
                Text(ScheduleMath.summary(prompt.schedule))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if viewModel.runningSchedules.contains(prompt.id) {
                    Label("Running now", systemImage: "hourglass")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                } else if prompt.enabled {
                    Text("Next: \(ScheduleMath.nextRun(after: Date(), prompt.schedule).formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Run now") { viewModel.runScheduledPromptNow(prompt.id) }
                .buttonStyle(GatitaButtonStyle(.secondary))
                .disabled(viewModel.runningSchedules.contains(prompt.id))
            Toggle("", isOn: Binding(get: { prompt.enabled }, set: { on in
                var changed = prompt
                changed.enabled = on
                // Turning a prompt back on starts from now, so it does not catch up on runs from while it was off.
                if on { changed.lastRun = Date() }
                viewModel.saveScheduledPrompt(changed)
            }))
            .labelsHidden()
            .toggleStyle(.switch)
            Button { edit(prompt) } label: { Image(systemName: "pencil").foregroundStyle(.secondary) }
                .buttonStyle(.plain)
                .help("Edit")
            Button { viewModel.deleteScheduledPrompt(prompt.id) } label: { Image(systemName: "trash").foregroundStyle(.secondary) }
                .buttonStyle(.plain)
                .help("Delete")
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Name, such as Morning news", text: $draft.name)
                .textFieldStyle(.plain)
                .padding(10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            TextEditor(text: $draft.prompt)
                .font(.callout)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 110)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if draft.prompt.isEmpty {
                        Text("The prompt, such as: Summarize today's top tech news in five bullets.")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .padding(11)
                            .allowsHitTesting(false)
                    }
                }
            GatitaTabs(options: [GatitaMode.chat, GatitaMode.code], selection: $draft.mode,
                       title: { $0 == .code ? "Code" : "Chat" })
            GatitaTabs(options: Schedule.Repeat.allCases, selection: $draft.repeats, title: \.title)
            HStack {
                if draft.repeats == .weekly {
                    Picker("Day", selection: $draft.weekday) {
                        ForEach(1...7, id: \.self) { day in
                            Text(Calendar.current.weekdaySymbols[day - 1]).tag(day)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                DatePicker("Time", selection: $draft.time, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                Spacer()
            }
        }
    }

    private func edit(_ prompt: ScheduledPrompt?) {
        if let prompt {
            draft = Draft(id: prompt.id, name: prompt.name, prompt: prompt.prompt, mode: prompt.mode,
                          repeats: prompt.schedule.repeats,
                          time: Calendar.current.date(from: DateComponents(hour: prompt.schedule.hour,
                                                                           minute: prompt.schedule.minute)) ?? Date(),
                          weekday: prompt.schedule.weekday ?? 2)
        } else {
            draft = Draft()
        }
        dialog = GatitaDialogSpec(icon: "calendar.badge.clock", title: prompt == nil ? "New scheduled prompt" : "Edit scheduled prompt",
                                  confirm: "Save", closesOnOutsideTap: false)
    }

    private func save() {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !text.isEmpty else { return }
        let time = Calendar.current.dateComponents([.hour, .minute], from: draft.time)
        let schedule = Schedule(repeats: draft.repeats, hour: time.hour ?? 8, minute: time.minute ?? 0,
                                weekday: draft.repeats == .weekly ? draft.weekday : nil)
        let old = viewModel.scheduledPrompts.first { $0.id == draft.id }
        viewModel.saveScheduledPrompt(ScheduledPrompt(id: draft.id ?? UUID(), name: name, prompt: text, mode: draft.mode,
                                                      schedule: schedule, enabled: old?.enabled ?? true,
                                                      createdAt: old?.createdAt ?? Date(), lastRun: old?.lastRun ?? Date()))
    }

    private func setLoginItem(_ on: Bool) {
        loginProblem = nil
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            loginProblem = "macOS did not change it: \(error.localizedDescription)"
        }
        loginItem = SMAppService.mainApp.status
    }
}
#endif

//
//  SettingsMenu.swift
//  Gatita
//

import SwiftUI

/// Settings as a main menu. The account and usage are at the top. Each part of the app has its own page.
struct HostSettingsView: View {
    @Bindable var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    /// Dialogs open on a page of Settings, such as New skill. Escape closes them, not the whole sheet.
    @State private var escape = EscapeClaims()

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            GatitaSheetHeader(title: "Settings", escapeCloses: !escape.isClaimed, onClose: { dismiss() })
            menu
        }
        .background(Theme.background)
        .environment(escape)
        #else
        menu
        #endif
    }

    private var menu: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        AccountSettingsView(viewModel: viewModel)
                    } label: {
                        accountRow
                    }
                    NavigationLink {
                        UsageSettingsView(viewModel: viewModel)
                    } label: {
                        Label("Usage", systemImage: "chart.bar")
                    }
                }

                Section("Features") {
                    NavigationLink {
                        InstructionsSettingsView(viewModel: viewModel)
                    } label: {
                        menuRow("Instructions", "text.badge.checkmark",
                                subtitle: viewModel.customInstructions.isEmpty ? "None" : "Read before every reply")
                    }
                    NavigationLink {
                        MemorySettingsView(viewModel: viewModel)
                    } label: {
                        menuRow("Memory", "brain", subtitle: !viewModel.memoryEnabled ? "Off"
                                : viewModel.memories.count == 1 ? "1 fact" : "\(viewModel.memories.count) facts")
                    }
                    NavigationLink {
                        PairingSettingsView(viewModel: viewModel)
                    } label: {
                        menuRow("Pairing", "link", subtitle: pairingSubtitle)
                    }
                    NavigationLink {
                        PluginsSettingsView(viewModel: viewModel)
                    } label: {
                        menuRow("Plugins", "puzzlepiece.extension", subtitle: "\(viewModel.plugins.details.count) installed")
                    }
                    NavigationLink {
                        SkillsSettingsView(viewModel: viewModel)
                    } label: {
                        menuRow("Skills", "slider.horizontal.3", subtitle: "\(viewModel.skills.count) available")
                    }
                    NavigationLink {
                        MCPSettingsView(viewModel: viewModel)
                    } label: {
                        menuRow("MCP Servers", "server.rack", subtitle: mcpSubtitle)
                    }
                    NavigationLink {
                        ConnectorsSettingsView(viewModel: viewModel)
                    } label: {
                        menuRow("Connectors", "point.3.connected.trianglepath.dotted", subtitle: "\(viewModel.connectors.count) on")
                    }
                    #if os(macOS)
                    NavigationLink {
                        ScheduledSettingsView(viewModel: viewModel)
                    } label: {
                        menuRow("Scheduled", "calendar.badge.clock",
                                subtitle: viewModel.scheduledPrompts.isEmpty ? "None"
                                    : "\(viewModel.scheduledPrompts.filter(\.enabled).count) on")
                    }
                    NavigationLink {
                        QuickPanelSettingsView(viewModel: viewModel)
                    } label: {
                        menuRow("Quick panel", "command", subtitle: viewModel.doubleCommandOpensPanel ? "⌘⌘ or ⌃⌘G" : "⌃⌘G")
                    }
                    NavigationLink {
                        ProjectSettingsView(viewModel: viewModel)
                    } label: {
                        menuRow("Project", "folder", subtitle: viewModel.projectRoot.isEmpty ? "No folder set" : viewModel.projectRoot)
                    }
                    #endif
                }

                Section("App") {
                    NavigationLink {
                        TranscriptSettingsView(viewModel: viewModel)
                    } label: {
                        menuRow("Transcript view", "text.alignleft", subtitle: viewModel.transcriptView.title)
                    }
                    NavigationLink {
                        AboutSettingsView()
                    } label: {
                        menuRow("About", "info.circle", subtitle: AppVersion.display)
                    }
                    NavigationLink {
                        LogsSettingsView(viewModel: viewModel)
                    } label: {
                        menuRow("Logs and analytics", "doc.text.magnifyingglass", subtitle: "Stay on this device")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Settings")
        }
    }

    private var accountName: String {
        let name = NSFullUserName()
        return name.isEmpty ? "Gatita" : name
    }

    private var accountRow: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Theme.surface)
                .frame(width: 40, height: 40)
                .overlay(Text(String(accountName.prefix(1))).font(.headline))
            VStack(alignment: .leading, spacing: 2) {
                Text(accountName)
                    .font(.headline)
                Text(viewModel.apiKey.isEmpty ? "No Gatita key yet" : "Key saved, ending \(String(viewModel.apiKey.suffix(4)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var mcpSubtitle: String {
        guard !viewModel.mcpServers.isEmpty else { return "None" }
        let connected = viewModel.mcp.status.values.filter { if case .connected = $0 { true } else { false } }.count
        return "\(connected) of \(viewModel.mcpServers.count) connected"
    }

    private var pairingSubtitle: String {
        #if os(macOS)
        if viewModel.isPairingOpen, let code = viewModel.pairingCode {
            return "Open, code \(code)"
        }
        return "Closed"
        #else
        if let name = viewModel.remoteMac.connectedName {
            return "Connected to \(name)"
        }
        return "Not connected"
        #endif
    }

    private func menuRow(_ title: String, _ icon: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The Gatita key and the model.
struct AccountSettingsView: View {
    @Bindable var viewModel: ChatViewModel

    var body: some View {
        List {
            Section {
                SecureField("Paste your API key", text: $viewModel.apiKey)
                Button("Forget saved key", role: .destructive) {
                    viewModel.apiKey = ""
                }
                .disabled(viewModel.apiKey.isEmpty)
                SettingsNote(Text("The key is saved in the Keychain, not in settings.json."))
            } header: {
                Text("Gatita key")
            }

            Section("Model") {
                ForEach(ChatViewModel.models, id: \.self) { model in
                    Button {
                        viewModel.model = model
                    } label: {
                        HStack {
                            Text(ChatViewModel.displayName(for: model))
                            Spacer()
                            if viewModel.model == model {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Account")
    }
}

/// What this app did on this device. Gatita publishes no usage API, so the page counts local events only.
struct UsageSettingsView: View {
    @Bindable var viewModel: ChatViewModel

    var body: some View {
        let counts = viewModel.analytics.summary()
        let toolCalls = counts.filter { $0.key.hasPrefix("tool:") }.values.reduce(0, +)
        let failures = counts.filter { $0.key.hasPrefix("failure:") }.values.reduce(0, +)
        List {
            Section("On this device") {
                LabeledContent("Saved chats", value: "\(viewModel.conversations.count)")
                LabeledContent("Messages sent", value: "\(counts["message_sent"] ?? 0)")
                LabeledContent("Tool calls", value: "\(toolCalls)")
                LabeledContent("Failures", value: "\(failures)")
            }
            Section {
                Text("Gatita has no usage or account API, so this page counts what this app did here. Token counts are not tracked yet. Plans and usage are on gatita.tech.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Usage")
    }
}

/// Pair this device with a Mac or another device that has the same code.
struct PairingSettingsView: View {
    @Bindable var viewModel: ChatViewModel

    var body: some View {
        List {
            Section {
                TimelineView(.periodic(from: .now, by: 15)) { _ in
                    if viewModel.isPairingOpen, let until = viewModel.pairingOpenUntil {
                        if let code = viewModel.pairingCode {
                            Text(code)
                                .font(.system(size: 40, weight: .bold, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity)
                        }
                        Text("Devices can pair until \(until.formatted(date: .omitted, time: .shortened)).")
                            .foregroundStyle(.secondary)
                        Button("Stop allowing devices", role: .destructive) {
                            viewModel.closePairing()
                        }
                    } else {
                        Button("Allow devices for 5 minutes") {
                            viewModel.openPairing()
                        }
                    }
                }
                SettingsNote(Text("Allowing devices makes a new code. A phone or iPad needs it to pair, and it stops working when the time is up."))
            } header: {
                Text("Allow pairing")
            }

            #if !os(macOS)
            Section {
                SecureField("Code shown on your Mac", text: $viewModel.remoteCode)
                SettingsNote(Text("Type the code your Mac shows, then connect to it below."))
            } header: {
                Text("Pairing code")
            }
            #endif

            #if !os(macOS)
            Section {
                if !viewModel.remoteMac.status.isEmpty {
                    Text(viewModel.remoteMac.status)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Nearby") {
                if viewModel.remoteMac.found.isEmpty {
                    Text("No devices found yet. Open Gatita on your Mac, and allow Local Network for Gatita in Privacy & Security.")
                        .foregroundStyle(.secondary)
                }
                ForEach(viewModel.remoteMac.found) { device in
                    Button("Connect to \(device.id)") {
                        viewModel.remoteMac.connect(to: device, code: viewModel.remoteCode)
                    }
                }
            }
            #endif
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Pairing")
    }
}

/// Installed plugins: each one adds skills and, on the Mac, allowed commands.
struct PluginsSettingsView: View {
    @Bindable var viewModel: ChatViewModel

    var body: some View {
        List {
            Section {
                if viewModel.plugins.details.isEmpty {
                    Text("No plugins loaded.")
                        .foregroundStyle(.secondary)
                }
                ForEach(viewModel.plugins.details) { plugin in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("!\(plugin.name)")
                            .font(.callout.weight(.medium))
                        Text(plugin.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Skills: " + plugin.skillNames.joined(separator: ", "))
                            .font(.caption)
                        if !plugin.commands.isEmpty {
                            Text("Commands: " + plugin.commands.joined(separator: ", "))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                SettingsNote(Text("Add a folder with a plugin.json to \(Plugins.defaultDirectory.path), then reload."))
            }

            Section {
                Button("Reload plugins") {
                    viewModel.reloadPlugins()
                }
                #if os(macOS)
                Button("Open plugins folder") {
                    try? FileManager.default.createDirectory(at: Plugins.defaultDirectory, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(Plugins.defaultDirectory)
                }
                #endif
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Plugins")
    }
}

/// Skills the message box can use. Type / to pick one.
#if os(macOS)
/// How the quick panel opens: ⌘ pressed twice (which needs Input Monitoring permission) and ⌃⌘G.
struct QuickPanelSettingsView: View {
    @Bindable var viewModel: ChatViewModel
    private var controller: QuickPanelController { .shared }

    var body: some View {
        List {
            Section {
                Toggle("Press ⌘ twice to open the quick panel", isOn: $viewModel.doubleCommandOpensPanel)
                if viewModel.doubleCommandOpensPanel {
                    switch controller.doubleTapStatus {
                    case .running:
                        Label("On. Press ⌘ twice, quickly, in any app.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .needsPermission:
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Gatita needs Input Monitoring permission to notice ⌘ in other apps. Turn Gatita on in the list, then come back here.",
                                  systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            HStack(spacing: 8) {
                                Button("Open Input Monitoring") { CommandDoubleTap.openPrivacySettings() }
                                    .buttonStyle(GatitaButtonStyle(.primary))
                                Button("Check again") { controller.refreshStatus() }
                                    .buttonStyle(GatitaButtonStyle(.secondary))
                            }
                        }
                    case .off:
                        Text("Starting…")
                            .foregroundStyle(.secondary)
                    }
                }
                SettingsNote(Text("⌃⌘G and Chat, then Quick Panel, always open it too. Gatita only reads whether ⌘ was pressed on its own; it never records what you type."))
            }

            Section {
                Toggle("⌘⌘ starts with a screenshot", isOn: $viewModel.doubleCommandTakesScreenshot)
                if ScreenCapture.isAllowed {
                    Label("Screen Recording is allowed.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Screenshots need Screen Recording permission. Turn Gatita on in the list.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Button("Open Screen Recording") {
                            ScreenCapture.requestPermission()
                            ScreenCapture.openPrivacySettings()
                        }
                        .buttonStyle(GatitaButtonStyle(.primary))
                    }
                }
                SettingsNote(Text("Like Claude's quick entry: ⌘⌘ opens the panel and dims the screens. Drag over an area, or click a window, and the screenshot is attached to the panel, which is left out of the picture. Escape, or a click on the panel, skips it. The camera button takes one any time. Nothing is sent until you press Return."))
            } header: {
                Text("Screenshots")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Quick panel")
        .onAppear { controller.refreshStatus() }
    }
}
#endif

struct SkillsSettingsView: View {
    @Bindable var viewModel: ChatViewModel
    @State private var dialog: GatitaDialogSpec?
    @State private var editingID: String?
    @State private var name = ""
    @State private var instructions = ""

    var body: some View {
        List {
            Section {
                ForEach(viewModel.mySkills) { skill in
                    HStack(alignment: .top) {
                        skillRow(skill)
                        Spacer()
                        Button {
                            edit(skill)
                        } label: {
                            Image(systemName: "pencil")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Edit")
                        Button {
                            viewModel.deleteMySkill(skill.id)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Delete")
                    }
                }
                Button {
                    edit(nil)
                } label: {
                    Label("New skill", systemImage: "plus")
                }
                .buttonStyle(GatitaButtonStyle(.primary))
                .padding(.vertical, 4)
                SettingsNote(Text("Your own instructions, such as a writing style or a checklist. Pick one with / like any other skill."))
            } header: {
                Text("My skills")
            }

            Section {
                ForEach(viewModel.skills.filter { !$0.id.hasPrefix("my-") }) { skill in
                    skillRow(skill)
                }
                SettingsNote(Text("Type / in the message box to use a skill. Plugins add more."))
            } header: {
                Text("Built in and from plugins")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Skills")
        .gatitaDialog($dialog, onConfirm: {
            viewModel.saveMySkill(id: editingID, name: name, instructions: instructions)
        }) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Name, such as Email writer", text: $name)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                TextEditor(text: $instructions)
                    .font(.callout)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 140)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        if instructions.isEmpty {
                            Text("What Gatita should do, such as: Write short, friendly emails. End with one clear question.")
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                                .padding(11)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
    }

    private func skillRow(_ skill: Skill) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(skill.name)
                .font(.callout.weight(.medium))
            Text("/\(skill.id)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    private func edit(_ skill: Skill?) {
        editingID = skill?.id
        name = skill?.name ?? ""
        instructions = skill?.instructions ?? ""
        dialog = GatitaDialogSpec(icon: "slider.horizontal.3", title: skill == nil ? "New skill" : "Edit skill",
                                  confirm: "Save", closesOnOutsideTap: false)
    }
}

/// Connectors read outside services. Turning one on keeps it on for the chat.
struct ConnectorsSettingsView: View {
    @Bindable var viewModel: ChatViewModel

    private func binding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { viewModel.connectors.contains(id) },
            set: { isOn in
                if isOn { viewModel.connectors.insert(id) } else { viewModel.connectors.remove(id) }
            })
    }

    var body: some View {
        List {
            Section {
                ForEach(Connectors.catalog.filter { HostPolicy.allows($0) }) { connector in
                    VStack(alignment: .leading, spacing: 3) {
                        Toggle("!\(connector.id)  \(connector.name)", isOn: binding(connector.id))
                        Text(connector.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                SettingsNote(Text("GitHub uses your gh login on the Mac, and works only in Code with a project. Gmail needs a Google sign-in set up first, so it is not here yet."))
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Connectors")
    }
}

#if os(macOS)
/// The project folder and what Gatita may do in it.
struct ProjectSettingsView: View {
    @Bindable var viewModel: ChatViewModel

    var body: some View {
        List {
            Section {
                TextField("e.g. ~/Documents/Gatita", text: $viewModel.projectRoot)
            } header: {
                Text("Project folder")
            }
            Section {
                Toggle("Let Gatita edit files in the project", isOn: $viewModel.allowWrites)
                Toggle("Let Gatita run allowed commands (sandboxed, no network)", isOn: $viewModel.allowCommands)
                Toggle("Ask before each command", isOn: $viewModel.askBeforeCommands)
                    .disabled(!viewModel.allowCommands)
                Toggle("Keep the Mac awake while Gatita is open", isOn: $viewModel.keepAwake)
            }
            if viewModel.askBeforeCommands, !viewModel.projectCommandRules.isEmpty {
                Section {
                    ForEach(viewModel.projectCommandRules, id: \.self) { rule in
                        HStack {
                            Text(rule)
                                .font(.callout.monospaced())
                            Spacer()
                            Button {
                                viewModel.removeCommandRule(rule)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Ask again before \(rule)")
                        }
                    }
                    SettingsNote(Text("Each covers that command with any arguments. Remove one to be asked again."))
                } header: {
                    Text("Always allowed in this project")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Project")
    }
}
#endif

struct AboutSettingsView: View {
    var body: some View {
        List {
            Section {
                Text("Gatita \(AppVersion.display)")
                    .font(.callout.weight(.medium))
                    SettingsNote(Text("Versions go MAJOR.MINOR.PATCH: a big refactor, then new models, then updates and fixes. No number resets. See CHANGELOG.md."))
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("About")
    }
}

struct LogsSettingsView: View {
    @Bindable var viewModel: ChatViewModel

    private var analyticsSummary: String {
        let counts = viewModel.analytics.summary().sorted { $0.key < $1.key }
        return counts.isEmpty ? "No events yet." : counts.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
    }

    var body: some View {
        List {
            Section {
                Text(analyticsSummary)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    SettingsNote(Text("Stays on this device."))
            } header: {
                Text("Analytics")
            }

            #if os(macOS)
            Section {
                Button("Open logs folder") {
                    NSWorkspace.shared.open(AppLog.defaultDirectory)
                }
                Button("Open settings folder") {
                    NSWorkspace.shared.open(SettingsStore.defaultFile.deletingLastPathComponent())
                }
            }
            #endif
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Logs and analytics")
    }
}

/// How much of each reply the chat shows.
struct TranscriptSettingsView: View {
    @Bindable var viewModel: ChatViewModel

    var body: some View {
        List {
            Section {
                Picker("Transcript view", selection: $viewModel.transcriptView) {
                    ForEach(TranscriptView.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                SettingsNote(Text("Normal shows only what Gatita writes. Thinking adds its thinking and tool calls, folded. Verbose shows everything open."))
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Transcript view")
    }
}

/// Your own instructions. Gatita reads them before every reply, the way a system prompt works.
/// What Gatita remembers about you: each fact with a delete button, a box to add one, and a switch for all of it.
struct MemorySettingsView: View {
    @Bindable var viewModel: ChatViewModel
    @State private var newFact = ""
    @State private var problem: String?
    @State private var dialog: GatitaDialogSpec?

    var body: some View {
        List {
            Section {
                Toggle("Remember things about me", isOn: $viewModel.memoryEnabled)
                SettingsNote(Text("Gatita saves short facts you tell it, such as your name or how you like answers, and reads them before every reply in every chat. They stay on this device. Passwords, keys, and card numbers are never saved."))
            }

            if viewModel.memoryEnabled {
                Section {
                    if viewModel.memories.isEmpty {
                        Text("Nothing yet. Tell Gatita something about you, or add a fact here.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(viewModel.memories) { fact in
                        HStack(alignment: .firstTextBaseline) {
                            Text(fact.text)
                            Spacer()
                            Button {
                                viewModel.deleteMemory(fact.id)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Forget this")
                        }
                    }
                    HStack {
                        TextField("Add a fact, such as: I'm learning Swift", text: $newFact)
                            .textFieldStyle(.plain)
                            .onSubmit(add)
                        Button("Add", action: add)
                            .buttonStyle(GatitaButtonStyle(.primary))
                            .disabled(newFact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if let problem {
                        Text(problem)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("What Gatita remembers (\(viewModel.memories.count) of \(MemoryStore.maxFacts))")
                }

                if !viewModel.memories.isEmpty {
                    Section {
                        Button("Forget everything…", role: .destructive) {
                            dialog = GatitaDialogSpec(icon: "brain", title: "Forget everything?",
                                                      message: "Gatita forgets all \(viewModel.memories.count) facts about you. This can't be undone.",
                                                      confirm: "Forget everything", role: .destructive)
                        }
                        .buttonStyle(GatitaButtonStyle(.destructive))
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Memory")
        .onAppear { viewModel.reloadMemories() }
        .gatitaDialog($dialog, onConfirm: { viewModel.forgetAllMemories() })
    }

    private func add() {
        problem = viewModel.addMemory(newFact)
        if problem == nil { newFact = "" }
    }
}

struct InstructionsSettingsView: View {
    @Bindable var viewModel: ChatViewModel

    var body: some View {
        List {
            Section {
                TextEditor(text: $viewModel.customInstructions)
                    .frame(minHeight: 180)
                    SettingsNote(Text("Gatita reads these before every reply, for example how to answer or what to call you. Up to \(CustomInstructions.maxCharacters) characters."))
            } header: {
                Text("Your instructions")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Instructions")
    }
}

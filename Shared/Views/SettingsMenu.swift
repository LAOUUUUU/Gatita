//
//  SettingsMenu.swift
//  Gatita
//

import SwiftUI

/// Settings as a main menu. The account and usage are at the top. Each part of the app has its own page.
struct HostSettingsView: View {
    @Bindable var viewModel: ChatViewModel

    var body: some View {
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
                        ConnectorsSettingsView(viewModel: viewModel)
                    } label: {
                        menuRow("Connectors", "point.3.connected.trianglepath.dotted", subtitle: "\(viewModel.connectors.count) on")
                    }
                    #if os(macOS)
                    NavigationLink {
                        ProjectSettingsView(viewModel: viewModel)
                    } label: {
                        menuRow("Project", "folder", subtitle: viewModel.projectRoot.isEmpty ? "No folder set" : viewModel.projectRoot)
                    }
                    #endif
                }

                Section("App") {
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
            } header: {
                Text("Gatita key")
            } footer: {
                Text("The key is saved in the Keychain, not in settings.json.")
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
            } header: {
                Text("Allow pairing")
            } footer: {
                Text("Allowing devices makes a new code. A phone or iPad needs it to pair, and it stops working when the time is up.")
            }

            #if !os(macOS)
            Section {
                SecureField("Code shown on your Mac", text: $viewModel.remoteCode)
            } header: {
                Text("Pairing code")
            } footer: {
                Text("Type the code your Mac shows, then connect to it below.")
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
            } footer: {
                Text("Add a folder with a plugin.json to \(Plugins.defaultDirectory.path), then reload.")
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
struct SkillsSettingsView: View {
    @Bindable var viewModel: ChatViewModel

    var body: some View {
        List {
            Section {
                ForEach(viewModel.skills) { skill in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(skill.name)
                            .font(.callout.weight(.medium))
                        Text("/\(skill.id)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Type / in the message box to use a skill. Plugins add more.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Skills")
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
            } footer: {
                Text("GitHub uses your gh login on the Mac, and works only in Code with a project. Gmail needs a Google sign-in set up first, so it is not here yet.")
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
                Toggle("Keep the Mac awake while Gatita is open", isOn: $viewModel.keepAwake)
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
            } footer: {
                Text("Versions go MAJOR.MINOR.PATCH: a big refactor, then new models, then updates and fixes. No number resets. See CHANGELOG.md.")
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
            } header: {
                Text("Analytics")
            } footer: {
                Text("Stays on this device.")
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

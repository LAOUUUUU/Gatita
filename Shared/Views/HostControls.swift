//
//  HostControls.swift
//  Gatita
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

/// One row in the "/" or "@" menu.
private struct Suggestion: Identifiable {
    enum Action {
        case skill(String)
        case insert(String)
    }

    let id: String
    let title: String
    let detail: String
    let action: Action
}

/// Prompt field for a host device (Mac or iPhone), which calls Gatita directly.
/// Type "/" at the start for skills, "@" for project files, or "!" for plugins. The send button turns into a stop button while a reply is streaming.
struct HostInputBar: View {
    @Bindable var viewModel: ChatViewModel
    @State private var input = ""

    private var isEmpty: Bool {
        input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var token: ComposerToken? {
        Composer.activeToken(in: input)
    }

    /// What the open menu offers: skills for "/", files for "@", and plugins for "!".
    private var suggestions: [Suggestion] {
        guard let token else { return [] }
        switch token.trigger {
        case .skill:
            return Composer.skills(matching: token.query, in: viewModel.skills).map {
                Suggestion(id: "skill:\($0.id)", title: "/\($0.id)", detail: $0.name, action: .skill($0.id))
            }
        case .plugin:
            let needle = token.query.lowercased()
            let pluginRows = viewModel.plugins.details
                .filter { needle.isEmpty || $0.name.lowercased().contains(needle) }
                .map {
                    Suggestion(id: "plugin:\($0.name)", title: "!\($0.name)",
                               detail: "plugin · \($0.description)", action: .insert("!\($0.name)"))
                }
            let connectorRows = Connectors.catalog
                .filter { needle.isEmpty || $0.id.contains(needle) || $0.name.lowercased().contains(needle) }
                .map {
                    Suggestion(id: "connector:\($0.id)", title: "!\($0.id)",
                               detail: "connector · \($0.name)", action: .insert("!\($0.id)"))
                }
            return pluginRows + connectorRows
        case .file:
            return Composer.files(matching: token.query, in: viewModel.projectFilePaths()).map {
                Suggestion(id: "file:\($0)", title: "@\($0)", detail: "file", action: .insert("@\($0)"))
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(suggestions.prefix(8)) { suggestion in
                        Button {
                            choose(suggestion)
                        } label: {
                            HStack(spacing: 8) {
                                Text(suggestion.title)
                                    .font(.callout.monospaced())
                                Text(suggestion.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 8)
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Menu {
                    Picker("Skill", selection: $viewModel.skillID) {
                        Text("No skill").tag(Skills.none)
                        ForEach(viewModel.skills) { skill in
                            Text(skill.name).tag(skill.id)
                        }
                    }
                } label: {
                    Label(skillName, systemImage: "wand.and.stars")
                        .labelStyle(.iconOnly)
                }
                #if os(macOS)
                .menuStyle(.borderlessButton)
                .fixedSize()
                #endif

                TextField("Ask Gatita…  (/ skills · @ files · ! plugins)", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        if let first = suggestions.first {
                            choose(first)
                        } else {
                            send()
                        }
                    }

                Menu {
                    Picker("Model", selection: $viewModel.model) {
                        ForEach(ChatViewModel.models, id: \.self) { model in
                            Text(ChatViewModel.displayName(for: model)).tag(model)
                        }
                    }
                } label: {
                    Text(ChatViewModel.displayName(for: viewModel.model))
                        .font(.callout)
                }
                #if os(macOS)
                .menuStyle(.borderlessButton)
                .fixedSize()
                #endif

                Button(action: primaryAction) {
                    Image(systemName: viewModel.isSending ? "stop.circle.fill" : "arrow.up.circle.fill")
                }
                .disabled(!viewModel.isSending && isEmpty)
            }
        }
        .padding()
    }

    private var skillName: String {
        viewModel.skills.first { $0.id == viewModel.skillID }?.name ?? "Skill"
    }

    private func choose(_ suggestion: Suggestion) {
        switch suggestion.action {
        case .skill(let id):
            viewModel.skillID = id
            input = ""
        case .insert(let text):
            input = Composer.replacingActiveToken(in: input, with: text)
        }
    }

    private func primaryAction() {
        if viewModel.isSending {
            viewModel.stop()
        } else {
            send()
        }
    }

    private func send() {
        let text = input
        input = ""
        viewModel.send(text)
    }
}

/// Key, project, plugin, and logging settings for a host device. The key is saved in the Keychain.
struct HostSettingsView: View {
    @Bindable var viewModel: ChatViewModel

    private func connectorBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { viewModel.connectors.contains(id) },
            set: { isOn in
                if isOn { viewModel.connectors.insert(id) } else { viewModel.connectors.remove(id) }
            })
    }

    private var analyticsSummary: String {
        let counts = viewModel.analytics.summary().sorted { $0.key < $1.key }
        return counts.isEmpty ? "No events yet." : counts.map { "\($0.key): \($0.value)" }.joined(separator: "   ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings are saved in settings.json. The API key is saved in the Keychain, not in that file.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Gatita API key (saved in Keychain)")
                .font(.caption)
                .foregroundStyle(.secondary)
            SecureField("Paste your API key", text: $viewModel.apiKey)
                .textFieldStyle(.roundedBorder)
            Button("Forget saved key", role: .destructive) {
                viewModel.apiKey = ""
            }
            .disabled(viewModel.apiKey.isEmpty)

            Text("Project folder")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("e.g. ~/Documents/Gatita", text: $viewModel.projectRoot)
                .textFieldStyle(.roundedBorder)

            Toggle("Let Gatita edit files in the project", isOn: $viewModel.allowWrites)
            Toggle("Let Gatita run allowed commands (sandboxed, no network)", isOn: $viewModel.allowCommands)

            Text("Connectors (mention !name in a message, or turn one on for the whole chat)")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(Connectors.catalog) { connector in
                VStack(alignment: .leading, spacing: 2) {
                    Toggle("!\(connector.id)  \(connector.name)", isOn: connectorBinding(connector.id))
                    Text(connector.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text("GitHub uses your gh login. Gmail and Calendar need a Google sign-in set up first, so they are not here yet.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Plugins")
                .font(.caption)
                .foregroundStyle(.secondary)
            if viewModel.plugins.details.isEmpty {
                Text("No plugins loaded. Add a folder with a plugin.json to \(Plugins.defaultDirectory.path), then press Reload.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(viewModel.plugins.details) { plugin in
                VStack(alignment: .leading, spacing: 2) {
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
            HStack {
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

            Text("Logs and analytics (stay on this Mac)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(analyticsSummary)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            #if os(macOS)
            Button("Open logs folder") {
                NSWorkspace.shared.open(AppLog.defaultDirectory)
            }
            Button("Open settings folder") {
                NSWorkspace.shared.open(SettingsStore.defaultFile.deletingLastPathComponent())
            }
            #endif
        }
        .padding(12)
        .frame(maxWidth: 480, alignment: .leading)
    }
}

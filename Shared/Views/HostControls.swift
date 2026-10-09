//
//  HostControls.swift
//  Gatita
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

/// One row in the "/", "@", or "!" menu.
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

/// The prompt box for a host device. Type "/" at the start for skills, "@" for project files, or "!" for plugins and connectors.
/// Skill and model choices open in a panel above the box, in the same dark style as the rest of Gatita.
struct HostInputBar: View {
    @Bindable var viewModel: ChatViewModel
    @State private var openPanel: Panel?

    private enum Panel: Equatable {
        case skill
        case model
    }

    private var draft: Binding<String> {
        Binding(get: { viewModel.draft }, set: { viewModel.draft = $0 })
    }

    private var isEmpty: Bool {
        viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// What the open menu offers: skills for "/", files for "@", and plugins and connectors for "!".
    private var suggestions: [Suggestion] {
        guard let token = Composer.activeToken(in: viewModel.draft) else { return [] }
        switch token.trigger {
        case .skill:
            return Composer.skills(matching: token.query, in: viewModel.skills).map {
                Suggestion(id: "skill:\($0.id)", title: "/\($0.id)", detail: $0.name, action: .skill($0.id))
            }
        case .file:
            return Composer.files(matching: token.query, in: viewModel.projectFilePaths()).map {
                Suggestion(id: "file:\($0)", title: "@\($0)", detail: "file", action: .insert("@\($0)"))
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
                .filter { HostPolicy.allows($0) }
                .filter { needle.isEmpty || $0.id.contains(needle) || $0.name.lowercased().contains(needle) }
                .map {
                    Suggestion(id: "connector:\($0.id)", title: "!\($0.id)",
                               detail: "connector · \($0.name)", action: .insert("!\($0.id)"))
                }
            return pluginRows + connectorRows
        }
    }

    private var skillName: String {
        viewModel.skills.first { $0.id == viewModel.skillID }?.name ?? "Skill"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let panel = openPanel {
                choicePanel(panel)
            }
            if !suggestions.isEmpty && openPanel == nil {
                suggestionList
            }
            promptRow
        }
        .frame(maxWidth: 760)
        .padding(.horizontal)
        .padding(.bottom, 4)
        .animation(.easeOut(duration: 0.15), value: openPanel)
    }

    /// Every control in the row is 30 points tall, so the icons, the model name, and the send button line up.
    private var promptRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Button {
                draft.wrappedValue += "@"
            } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help("Attach a project file with @")

            chipButton(.skill) {
                HStack(spacing: 3) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(Theme.accent)
            }
            .help(skillName)

            TextField("Ask anything", text: draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(1...10)
                .padding(.vertical, 6)
                .onSubmit {
                    if let first = suggestions.first {
                        choose(first)
                    } else {
                        send()
                    }
                }

            chipButton(.model) {
                HStack(spacing: 4) {
                    Text(ChatViewModel.displayName(for: viewModel.model))
                        .font(.callout)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(.secondary)
            }

            Button(action: primaryAction) {
                Image(systemName: viewModel.isSending ? "stop.fill" : "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Theme.accent.opacity(isEmpty && !viewModel.isSending ? 0.35 : 1)))
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.isSending && isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 24).fill(Theme.surface))
    }

    private func chipButton<Label: View>(_ panel: Panel, @ViewBuilder label: () -> Label) -> some View {
        Button {
            openPanel = openPanel == panel ? nil : panel
        } label: {
            label()
                .frame(height: 30)
                .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func choicePanel(_ panel: Panel) -> some View {
        HStack(spacing: 0) {
            if panel == .model {
                Spacer(minLength: 0)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    Text(panel == .skill ? "Skill" : "Model")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.top, 4)
                    if panel == .skill {
                        choiceRow(title: "No skill", detail: nil, selected: viewModel.skillID == Skills.none) {
                            viewModel.skillID = Skills.none
                            openPanel = nil
                        }
                        ForEach(viewModel.skills) { skill in
                            choiceRow(title: skill.name, detail: skill.id, selected: viewModel.skillID == skill.id) {
                                viewModel.skillID = skill.id
                                openPanel = nil
                            }
                        }
                    } else {
                        ForEach(ChatViewModel.models, id: \.self) { model in
                            choiceRow(title: ChatViewModel.displayName(for: model), detail: nil,
                                      selected: viewModel.model == model) {
                                viewModel.model = model
                                openPanel = nil
                            }
                        }
                    }
                }
                .padding(6)
            }
            .frame(width: 280)
            .frame(maxHeight: 320)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08)))
            if panel == .skill {
                Spacer(minLength: 0)
            }
        }
    }

    private func choiceRow(title: String, detail: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.callout)
                    if let detail {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Theme.accent.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var suggestionList: some View {
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
                .padding(.vertical, 4)
                .padding(.horizontal, 10)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08)))
    }

    private func choose(_ suggestion: Suggestion) {
        switch suggestion.action {
        case .skill(let id):
            viewModel.skillID = id
            viewModel.draft = ""
        case .insert(let text):
            viewModel.draft = Composer.replacingActiveToken(in: viewModel.draft, with: text)
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
        let text = viewModel.draft
        viewModel.draft = ""
        viewModel.send(text)
    }
}

/// Key, project, plugin, and logging settings for a host device. The key is saved in the Keychain.
struct HostSettingsView: View {
    @Bindable var viewModel: ChatViewModel

    private var analyticsSummary: String {
        let counts = viewModel.analytics.summary().sorted { $0.key < $1.key }
        return counts.isEmpty ? "No events yet." : counts.map { "\($0.key): \($0.value)" }.joined(separator: "   ")
    }

    private func connectorBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { viewModel.connectors.contains(id) },
            set: { isOn in
                if isOn { viewModel.connectors.insert(id) } else { viewModel.connectors.remove(id) }
            })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Settings are saved in settings.json. The API key is saved in the Keychain, not in that file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Card("Gatita") {
                    SecureField("Paste your API key", text: $viewModel.apiKey)
                        .textFieldStyle(.roundedBorder)
                    Button("Forget saved key", role: .destructive) {
                        viewModel.apiKey = ""
                    }
                    .disabled(viewModel.apiKey.isEmpty)
                }

                #if os(macOS)
                Card("Project") {
                    TextField("e.g. ~/Documents/Gatita", text: $viewModel.projectRoot)
                        .textFieldStyle(.roundedBorder)
                    Toggle("Let Gatita edit files in the project", isOn: $viewModel.allowWrites)
                    Toggle("Let Gatita run allowed commands (sandboxed, no network)", isOn: $viewModel.allowCommands)
                }
                #else
                Card("Project") {
                    Text("Project files, edits, and commands are on the Mac. Here Gatita answers questions and reads public web pages.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                #endif

                Card("Connectors") {
                    ForEach(Connectors.catalog.filter { HostPolicy.allows($0) }) { connector in
                        VStack(alignment: .leading, spacing: 2) {
                            Toggle("!\(connector.id)  \(connector.name)", isOn: connectorBinding(connector.id))
                            Text(connector.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("GitHub uses your gh login on the Mac. Gmail needs a Google sign-in set up first, so it is not here yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Card("Plugins") {
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
                        .buttonStyle(.bordered)
                        #if os(macOS)
                        Button("Open plugins folder") {
                            try? FileManager.default.createDirectory(at: Plugins.defaultDirectory, withIntermediateDirectories: true)
                            NSWorkspace.shared.open(Plugins.defaultDirectory)
                        }
                        .buttonStyle(.bordered)
                        #endif
                    }
                }

                Card("About") {
                    Text("Gatita \(AppVersion.display)")
                        .font(.callout.weight(.medium))
                    Text("Versions go MAJOR.MINOR.PATCH: a big refactor, then new models, then updates and fixes. No number resets. See CHANGELOG.md.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Card("Logs and analytics") {
                    Text("Stay on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(analyticsSummary)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    #if os(macOS)
                    HStack {
                        Button("Open logs folder") {
                            NSWorkspace.shared.open(AppLog.defaultDirectory)
                        }
                        .buttonStyle(.bordered)
                        Button("Open settings folder") {
                            NSWorkspace.shared.open(SettingsStore.defaultFile.deletingLastPathComponent())
                        }
                        .buttonStyle(.bordered)
                    }
                    #endif
                }
            }
            .padding()
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
    }
}

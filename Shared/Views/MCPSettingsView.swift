//
//  MCPSettingsView.swift
//  Gatita
//

import SwiftUI

/// Settings, MCP Servers: each server's state and tools, switches for on and trusted, and adding, changing,
/// restarting, and removing them. Kept in mcp.json, in the shape Claude Desktop uses, which can be imported.
struct MCPSettingsView: View {
    @Bindable var viewModel: ChatViewModel
    @State private var dialog: GatitaDialogSpec?
    @State private var draft = Draft()
    @State private var note: String?
    /// Why the server in the dialog can't be saved, such as a name already in use.
    @State private var problem: String?
    /// What the open dialog is for: adding or changing a server, trusting one, or importing.
    @State private var purpose: Purpose = .edit
    @State private var importing: [MCPServerConfig] = []

    private enum Purpose: Equatable {
        case edit
        case trust(String)
        case importServers
    }

    /// The server being added or changed in the dialog.
    struct Draft {
        enum Kind: String, CaseIterable, Identifiable {
            case local, remote
            var id: String { rawValue }
        }

        var editing: String?
        var name = ""
        var kind: Kind = .local
        var command = ""
        var arguments = ""
        var environment = ""
        var url = ""
    }

    var body: some View {
        List {
            Section {
                if viewModel.mcpServers.isEmpty {
                    Text("No MCP servers yet. An MCP server gives Gatita more tools, such as Notion, Linear, a database, or your files.")
                        .foregroundStyle(.secondary)
                }
                ForEach(viewModel.mcpServers) { server in
                    row(server)
                }
                HStack(spacing: 8) {
                    Button {
                        edit(nil)
                    } label: {
                        Label("Add server", systemImage: "plus")
                    }
                    .buttonStyle(GatitaButtonStyle(.primary))
                    #if os(macOS)
                    if FileManager.default.fileExists(atPath: MCPConfig.claudeDesktopFile.path) {
                        Button("Import from Claude Desktop", action: askImport)
                        .buttonStyle(GatitaButtonStyle(.secondary))
                    }
                    #endif
                }
                .padding(.vertical, 4)
                if let note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                SettingsNote(Text(footer))
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("MCP Servers")
        .gatitaDialog($dialog, onConfirm: confirm) {
            if purpose == .edit { editor }
        }
    }

    private var footer: String {
        #if os(macOS)
        var text = "Each tool call asks first, unless you trust the server. Local servers run programs on this Mac outside Gatita's command sandbox, with network access, so add only ones you trust. Tools of trusted servers also work in the quick panel and Shortcuts."
        if ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil {
            text += " This build runs in the App Sandbox, so only remote servers work."
        }
        return text
        #else
        return "Each tool call asks first, unless you trust the server. This device can use remote servers (an https address); local ones run on the Mac."
        #endif
    }

    private func row(_ server: MCPServerConfig) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(server.name)
                    .font(.callout.weight(.medium))
                Text(server.url ?? ([server.command ?? ""] + server.args).joined(separator: " "))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                status(server)
            }
            Spacer()
            // Trusting a server lets its tools run unasked, so turning it on asks first; turning it off does not.
            Toggle("Trusted", isOn: Binding(get: { server.trusted }, set: { on in
                if on { askTrust(server) } else { viewModel.setMCPServer(server.name, trusted: false) }
            }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("Run this server's tools without asking first")
            Toggle("", isOn: Binding(get: { !server.disabled }, set: { viewModel.setMCPServer(server.name, enabled: $0) }))
                .labelsHidden()
                .toggleStyle(.switch)
            Button { viewModel.reconnectMCPServer(server.name) } label: { Image(systemName: "arrow.clockwise").foregroundStyle(.secondary) }
                .buttonStyle(.plain)
                .disabled(server.disabled)
                .help("Restart")
            Button { edit(server) } label: { Image(systemName: "pencil").foregroundStyle(.secondary) }
                .buttonStyle(.plain)
                .help("Edit")
            Button { viewModel.removeMCPServer(server.name) } label: { Image(systemName: "trash").foregroundStyle(.secondary) }
                .buttonStyle(.plain)
                .help("Remove")
        }
    }

    @ViewBuilder
    private func status(_ server: MCPServerConfig) -> some View {
        switch server.disabled ? .off : viewModel.mcp.status[MCPConfig.serverKey(server.name)] ?? .off {
        case .off:
            Label("Off", systemImage: "circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .connecting:
            Label("Starting…", systemImage: "hourglass")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .connected(let tools):
            Label("\(tools) \(tools == 1 ? "tool" : "tools")", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed(let reason):
            Label("Could not start: \(reason)", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(3)
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            field("Name, such as github", text: $draft.name)
            if let problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            #if os(macOS)
            GatitaTabs(options: Draft.Kind.allCases, selection: $draft.kind,
                       title: { $0 == .local ? "Local (a command)" : "Remote (an address)" })
            #endif
            if draft.kind == .local {
                field("Command, such as npx", text: $draft.command)
                field("Arguments, such as -y @modelcontextprotocol/server-github", text: $draft.arguments)
                TextEditor(text: $draft.environment)
                    .font(.callout.monospaced())
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 70)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        if draft.environment.isEmpty {
                            Text("Environment, one KEY=value a line (optional)")
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                                .padding(11)
                                .allowsHitTesting(false)
                        }
                    }
            } else {
                field("https://example.com/mcp", text: $draft.url)
            }
        }
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .padding(10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func confirm() {
        switch purpose {
        case .edit: save()
        case .trust(let name): viewModel.setMCPServer(name, trusted: true)
        case .importServers:
            viewModel.importMCPServers(importing)
            note = "Added \(importing.count) \(importing.count == 1 ? "server" : "servers") from Claude Desktop."
        }
        purpose = .edit
    }

    private func askTrust(_ server: MCPServerConfig) {
        purpose = .trust(server.name)
        dialog = GatitaDialogSpec(icon: "checkmark.shield", title: "Trust \(server.name)?",
                                  message: "Its tools will run without asking first: in chats, the quick panel, Shortcuts, and scheduled prompts. Trust only servers you know well.",
                                  confirm: "Trust", role: .destructive)
    }

    private func askImport() {
        importing = viewModel.claudeDesktopServersToImport()
        guard !importing.isEmpty else {
            note = "Claude Desktop has no servers Gatita doesn't already have."
            return
        }
        purpose = .importServers
        dialog = GatitaDialogSpec(icon: "square.and.arrow.down",
                                  title: "Import \(importing.count) \(importing.count == 1 ? "server" : "servers") from Claude Desktop?",
                                  message: importing.map(\.name).joined(separator: ", ") + ". Local ones start right away, running their commands on this Mac, so import only servers you trust.",
                                  confirm: "Import")
    }

    private func edit(_ server: MCPServerConfig?) {
        purpose = .edit
        if let server {
            draft = Draft(editing: server.name, name: server.name, kind: server.isRemote ? .remote : .local,
                          command: server.command ?? "", arguments: MCPConfig.joinArguments(server.args),
                          environment: MCPConfig.environmentText(server.env), url: server.url ?? "")
        } else {
            draft = Draft()
            #if !os(macOS)
            draft.kind = .remote
            #endif
        }
        problem = nil
        dialog = GatitaDialogSpec(icon: "point.3.connected.trianglepath.dotted",
                                  title: server == nil ? "Add MCP server" : "Edit \(server!.name)",
                                  confirm: "Save", closesOnOutsideTap: false)
    }

    private func save() {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let reason = MCPConfig.nameProblem(name, among: viewModel.mcpServers, editing: draft.editing) {
            // The dialog closes on Save, so it opens again with what was typed and the reason.
            problem = reason
            let spec = dialog
            DispatchQueue.main.async { dialog = spec ?? GatitaDialogSpec(icon: "point.3.connected.trianglepath.dotted",
                                                                          title: "Add MCP server", confirm: "Save",
                                                                          closesOnOutsideTap: false) }
            return
        }
        let old = viewModel.mcpServers.first { $0.name == draft.editing }
        let remote = draft.kind == .remote
        let server = MCPServerConfig(
            name: name,
            command: remote ? nil : draft.command.trimmingCharacters(in: .whitespaces),
            args: remote ? [] : MCPConfig.splitArguments(draft.arguments),
            env: remote ? [:] : MCPConfig.environment(from: draft.environment),
            url: remote ? draft.url.trimmingCharacters(in: .whitespaces) : nil,
            disabled: old?.disabled ?? false,
            trusted: old?.trusted ?? false)
        viewModel.saveMCPServer(server, replacing: draft.editing)
    }
}

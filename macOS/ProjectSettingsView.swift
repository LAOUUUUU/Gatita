//
//  ProjectSettingsView.swift
//  Gatita
//

import SwiftUI

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

//
//  ProjectFilesView.swift
//  Gatita
//

import SwiftUI

#if os(macOS)
/// The project's files as a tree. Folders expand in place; click a file to read it.
struct ProjectFilesView: View {
    let tools: ProjectTools?
    @State private var nodes: [FileNode] = []
    @State private var loadError: String?
    @State private var openedFile: FileNode?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Files")
                    .font(.headline)
                Spacer()
                Button(action: reload) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(tools == nil)
            }
            .padding(10)
            Divider()

            if let loadError {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
            } else if tools == nil {
                Text("Set a project folder in Settings to see its files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
            } else {
                List(nodes, children: \.children) { node in
                    if node.isDirectory {
                        Label(node.name, systemImage: "folder")
                            .foregroundStyle(.secondary)
                    } else {
                        Button {
                            openedFile = node
                        } label: {
                            Label(node.name, systemImage: "doc.text")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .onAppear(perform: reload)
        .sheet(item: $openedFile) { node in
            if let tools {
                FileContentView(tools: tools, file: node)
            }
        }
    }

    private func reload() {
        guard let tools else {
            nodes = []
            loadError = nil
            return
        }
        do {
            nodes = try tools.tree()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

/// Shows one project file as plain text.
struct FileContentView: View {
    let tools: ProjectTools
    let file: FileNode
    @Environment(\.dismiss) private var dismiss
    @State private var content = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(file.path)
                    .font(.headline.monospaced())
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            ScrollView([.vertical, .horizontal]) {
                Text(content)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .frame(width: 720, height: 520)
        .onAppear {
            content = (try? tools.readText(file.path)) ?? "Could not read this file."
        }
    }
}
#endif

//
//  PullRequestView.swift
//  Gatita
//

import SwiftUI

#if os(macOS)
private func makeBranchName() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmm"
    return "gatita/changes-" + formatter.string(from: Date())
}

/// The diff and the text of new files for the chosen paths, trimmed so it fits a request.
nonisolated enum PullRequestDiff {
    static func text(for files: [String], in folder: URL) -> String {
        var parts: [String] = []
        if let tracked = try? HostProcess.run(["git", "diff", "HEAD", "--"] + files, in: folder), !tracked.isEmpty {
            parts.append(tracked)
        }
        let untracked = (try? HostProcess.run(["git", "ls-files", "--others", "--exclude-standard", "--"] + files, in: folder)) ?? ""
        for path in untracked.components(separatedBy: "\n") where !path.isEmpty {
            let contents = (try? String(contentsOf: folder.appendingPathComponent(path), encoding: .utf8)) ?? ""
            parts.append("New file \(path):\n" + String(contents.prefix(4_000)))
        }
        return String(parts.joined(separator: "\n\n").prefix(24_000))
    }
}

/// Review the changed files, name the branch and the pull request, then push and open it after one confirmation.
/// Only the files you tick are committed. Other staged changes are left alone.
struct PullRequestView: View {
    let folder: URL
    let analytics: Analytics
    let log: AppLog
    /// Asks Gatita for one reply with no tools. Used to write the title, description, and tags.
    let draft: (String) async throws -> String
    @Environment(\.dismiss) private var dismiss

    @State private var changes: [GitChange] = []
    @State private var selected: Set<String> = []
    /// The first git remote. Pull requests go there.
    @State private var remote: String?
    @State private var branch = makeBranchName()
    @State private var commitMessage = ""
    @State private var title = ""
    @State private var prBody = ""
    @State private var labelsText = ""
    @State private var base = "main"
    @State private var message = ""
    @State private var pullRequestURL: String?
    @State private var busy = false
    @State private var confirming = false

    private var canCreate: Bool {
        remote != nil && !busy && !selected.isEmpty
            && PullRequestPlan.isValidBranch(branch)
            && !commitMessage.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create pull request")
                .font(.title3.weight(.semibold))

            if let remote {
                Text("Pushes to remote \"\(remote)\"")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("This repo has no git remote yet, so a pull request can't be made. Add one with git remote add <name> <url>, then press Refresh.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            HStack {
                Text("Changed files")
                    .font(.headline)
                Spacer()
                Button("Select all") { selected = Set(changes.map(\.path)) }
                Button("Clear") { selected = [] }
                Button("Refresh", action: reload)
            }
            if changes.isEmpty {
                Text("No changes to commit.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                List(changes) { change in
                    Toggle(isOn: binding(for: change.path)) {
                        Text("\(label(for: change.kind))  \(change.path)")
                            .font(.callout.monospaced())
                    }
                }
                .frame(minHeight: 140, maxHeight: 220)
            }

            TextField("Branch", text: $branch)
            TextField("Commit message", text: $commitMessage)
            TextField("Pull request title (defaults to the commit message)", text: $title)
            TextField("Tags, comma separated (for example bug, ui)", text: $labelsText)
            TextField("Base branch", text: $base)
            TextEditor(text: $prBody)
                .font(.callout)
                .frame(minHeight: 80)

            HStack {
                Button("Draft with Gatita", action: draftWithGatita)
                    .disabled(busy || selected.isEmpty)
                Text("Reads the selected changes and fills in the title, description, and tags.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let pullRequestURL, let url = URL(string: pullRequestURL) {
                Link("Open pull request", destination: url)
            }
            if !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                if busy {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Create pull request…") { confirming = true }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
            }
        }
        .padding(18)
        .frame(width: 580)
        .onAppear(perform: reload)
        .confirmationDialog("Create this pull request?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Push and open pull request") { createPullRequest() }
        } message: {
            Text("This commits \(selected.count) file(s) on the new branch \(branch), pushes it to remote \"\(remote ?? "")\", and opens a pull request on GitHub.")
        }
    }

    private func binding(for path: String) -> Binding<Bool> {
        Binding(
            get: { selected.contains(path) },
            set: { isOn in
                if isOn { selected.insert(path) } else { selected.remove(path) }
            })
    }

    private func label(for kind: GitChange.Kind) -> String {
        switch kind {
        case .modified: return "M"
        case .added: return "A"
        case .deleted: return "D"
        case .renamed: return "R"
        case .untracked: return "?"
        case .other: return "·"
        }
    }

    private func reload() {
        remote = (try? HostProcess.run(["git", "remote"], in: folder))?
            .components(separatedBy: "\n")
            .first { !$0.isEmpty }
        do {
            changes = GitChanges.parse(try HostProcess.run(["git", "status", "--porcelain"], in: folder))
            selected = selected.intersection(changes.map(\.path))
        } catch {
            changes = []
            message = error.localizedDescription
        }
    }

    private func draftWithGatita() {
        let files = selected.sorted()
        guard !files.isEmpty else { return }
        busy = true
        message = "Gatita is writing the title, description, and tags…"
        let folder = folder
        Task {
            do {
                let diff = await Task.detached { PullRequestDiff.text(for: files, in: folder) }.value
                let reply = try await draft(PullRequestDraft.prompt(diff: diff))
                if let result = PullRequestDraft.parse(reply) {
                    title = result.title
                    prBody = result.body
                    labelsText = result.labels.joined(separator: ", ")
                    message = "Filled in from the changes. Review it, then create the pull request."
                } else {
                    message = "Gatita's reply had no usable title. Try again, or write the text yourself."
                }
            } catch {
                message = error.localizedDescription
            }
            busy = false
        }
    }

    private func createPullRequest() {
        guard let remote else { return }
        let headline = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let heading = title.isEmpty ? headline : title
        let tags = labelsText.split(separator: ",").map { String($0) }
        guard let steps = PullRequestPlan.steps(remote: remote, branch: branch, base: base, files: selected.sorted(),
                                                commitMessage: headline, title: heading, body: prBody,
                                                labels: tags) else {
            message = "Check the branch name, the commit message, and the selected files."
            return
        }

        busy = true
        message = "Working…"
        let folder = folder
        Task {
            do {
                var lastLine = ""
                for (index, step) in steps.enumerated() {
                    message = "Step \(index + 1) of \(steps.count): \(step.prefix(2).joined(separator: " "))"
                    let output = try await Task.detached { try HostProcess.run(step, in: folder) }.value
                    lastLine = output.components(separatedBy: "\n").last ?? ""
                }
                pullRequestURL = lastLine
                analytics.count("pull_request_created")
                log.info("pull request created from branch \(branch): \(lastLine)")
                message = "Pull request created."
                reload()
            } catch {
                analytics.count("pull_request_failed")
                let report = log.recordFailure(kind: "pull-request", message: error.localizedDescription,
                                               details: ["branch: \(branch)", "base: \(base)"])
                message = error.localizedDescription + (report.map { " Report saved: \($0)" } ?? "")
            }
            busy = false
        }
    }
}
#endif

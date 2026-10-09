//
//  GitChanges.swift
//  Gatita
//

import Foundation

/// One path that git reports as changed.
nonisolated struct GitChange: Equatable, Sendable, Identifiable {
    enum Kind: Sendable {
        case modified, added, deleted, renamed, untracked, other
    }

    let path: String
    let kind: Kind
    /// True when the change is already in the index (git add), so a commit would pick it up.
    let isStaged: Bool

    var id: String { path }
}

nonisolated enum GitChanges {
    /// Reads `git status --porcelain` output.
    static func parse(_ porcelain: String) -> [GitChange] {
        porcelain.components(separatedBy: "\n").compactMap { line -> GitChange? in
            guard line.count >= 4 else { return nil }
            let codes = Array(line.prefix(2))
            var rest = String(line.dropFirst(3))

            if codes == ["?", "?"] {
                return GitChange(path: rest, kind: .untracked, isStaged: false)
            }
            if let arrow = rest.range(of: " -> ") {
                rest = String(rest[arrow.upperBound...])
            }
            let code = codes.first { $0 != " " } ?? " "
            let kind: GitChange.Kind
            switch code {
            case "M": kind = .modified
            case "A": kind = .added
            case "D": kind = .deleted
            case "R": kind = .renamed
            default: kind = .other
            }
            return GitChange(path: rest, kind: kind, isStaged: codes[0] != " ")
        }
    }
}

/// Plans the steps that turn chosen files into a pull request. Nothing runs here; the caller runs each step in order.
nonisolated enum PullRequestPlan {
    /// Letters, digits, and - _ . / only, no "..", no leading "-", no trailing "/" or ".lock".
    static func isValidBranch(_ name: String) -> Bool {
        guard !name.isEmpty, !name.hasPrefix("-"), !name.hasSuffix("/"), !name.hasSuffix(".lock"),
              !name.contains(".."), !name.contains("//") else { return false }
        return name.allSatisfy { $0.isLetter || $0.isNumber || "-_./".contains($0) }
    }

    /// A tag in label form: lowercase words joined by "-", at most 30 characters.
    static func sanitizeLabel(_ label: String) -> String {
        let words = label.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        return String(words.joined(separator: "-").prefix(30))
    }

    /// The git and gh commands for a pull request, or nil if the inputs are not usable.
    static func steps(remote: String = "origin", branch: String, base: String, files: [String],
                      commitMessage: String, title: String, body: String, labels: [String] = []) -> [[String]]? {
        guard isValidBranch(branch), !base.isEmpty, !remote.isEmpty, !files.isEmpty,
              !commitMessage.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let tags = labels.map(sanitizeLabel).filter { !$0.isEmpty }
        let tagSteps = tags.map { ["gh", "label", "create", $0, "--force"] }
        let tagFlags = tags.flatMap { ["--label", $0] }
        return [
            ["git", "checkout", "-b", branch],
            ["git", "add", "--"] + files,
            ["git", "commit", "-m", commitMessage, "--"] + files,
            ["git", "push", "-u", remote, branch],
        ] + tagSteps + [
            ["gh", "pr", "create", "--base", base, "--head", branch, "--title", title, "--body", body] + tagFlags,
        ]
    }
}

/// The title, description, and tags for a pull request, written by Gatita from the diff.
nonisolated struct PullRequestDraft: Equatable, Sendable {
    let title: String
    let body: String
    let labels: [String]

    private nonisolated struct Payload: Decodable {
        let title: String?
        let body: String?
        let labels: [String]?
    }

    /// Finds the JSON object in a reply, even when the reply has other text around it.
    static func parse(_ reply: String) -> PullRequestDraft? {
        guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end,
              let data = String(reply[start...end]).data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let title = payload.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return nil
        }
        let labels = (payload.labels ?? []).map(PullRequestPlan.sanitizeLabel).filter { !$0.isEmpty }
        return PullRequestDraft(title: title, body: payload.body ?? "", labels: Array(labels.prefix(5)))
    }

    static func prompt(diff: String) -> String {
        """
        Write a pull request for the changes below. Reply with only one JSON object and no other text, in this shape:
        {"title": "short imperative title", "body": "a Markdown summary: what changed, why, and how to test", "labels": ["up to three lowercase tags such as bug, feature, ui, docs, refactor, tests"]}

        Changes:
        \(diff)
        """
    }
}

//
//  GitHubConnector.swift
//  Gatita
//

import Foundation

/// Helpers for the GitHub connector: reading a repo from a git remote, checking inputs, and formatting gh's JSON.
nonisolated enum GitHubConnector {
    /// "owner/repo" from an https or ssh GitHub remote, or nil for other hosts.
    static func repo(fromRemote url: String) -> String? {
        guard let range = url.range(of: "github.com") else { return nil }
        let rest = url[range.upperBound...]
        guard let separator = rest.first, separator == "/" || separator == ":" else { return nil }
        let parts = rest.dropFirst().split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        var repo = parts[1]
        if repo.hasSuffix(".git") { repo.removeLast(4) }
        guard !parts[0].isEmpty, !repo.isEmpty else { return nil }
        return parts[0] + "/" + repo
    }

    /// A pull request or issue number. Anything that is not a plain positive number is refused.
    static func number(_ text: String) -> Int? {
        guard !text.isEmpty, text.count <= 9, text.allSatisfy({ $0.isASCII && $0.isNumber }),
              let value = Int(text), value > 0 else { return nil }
        return value
    }

    static func state(_ text: String) -> String? {
        ["open", "closed", "merged", "all"].contains(text) ? text : nil
    }
}

/// Turns gh's JSON into short lines the model can read.
nonisolated enum GitHubFormat {
    private nonisolated struct Author: Decodable {
        let login: String
    }

    private nonisolated struct PullRequestRow: Decodable {
        let number: Int
        let title: String
        let author: Author?
        let headRefName: String?
        let url: String?
        let isDraft: Bool?
    }

    private nonisolated struct IssueRow: Decodable {
        let number: Int
        let title: String
        let state: String?
        let url: String?
        let author: Author?
    }

    static func pullRequests(json: String) -> String {
        guard let rows = decode([PullRequestRow].self, json) else { return "(could not read GitHub's reply)" }
        if rows.isEmpty { return "(none)" }
        return rows.map { row in
            var line = "#\(row.number) \(row.title) (\(row.author?.login ?? "unknown"), \(row.headRefName ?? ""))"
            if let url = row.url { line += " \(url)" }
            if row.isDraft == true { line += " [draft]" }
            return line
        }.joined(separator: "\n")
    }

    static func issues(json: String) -> String {
        guard let rows = decode([IssueRow].self, json) else { return "(could not read GitHub's reply)" }
        if rows.isEmpty { return "(none)" }
        return rows.map { row in
            var line = "#\(row.number) \(row.title) (\(row.state ?? ""), \(row.author?.login ?? "unknown"))"
            if let url = row.url { line += " \(url)" }
            return line
        }.joined(separator: "\n")
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ json: String) -> T? {
        try? JSONDecoder().decode(type, from: Data(json.utf8))
    }
}

#if os(macOS)
extension GitHubConnector {
    /// The GitHub repo of a project, read from its git remotes.
    static func repo(in root: URL) -> String? {
        let names = ((try? HostProcess.run(["git", "remote"], in: root)) ?? "")
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
        for name in names {
            if let url = try? HostProcess.run(["git", "remote", "get-url", name], in: root),
               let repo = repo(fromRemote: url) {
                return repo
            }
        }
        return nil
    }

    /// Runs one GitHub read with a fixed gh command. Nothing else can be run from here.
    static func run(_ tool: String, arguments: [String: String], root: URL) throws -> String {
        guard let repo = repo(in: root) else { throw ToolError("no GitHub remote was found in this project") }

        func gh(_ parts: [String]) throws -> String {
            try HostProcess.run(["gh"] + parts + ["--repo", repo], in: root)
        }
        func requiredNumber() throws -> String {
            guard let value = number(arguments["number"] ?? "") else {
                throw ToolError("number must be a whole number, such as 12")
            }
            return String(value)
        }
        func capped(_ text: String) -> String {
            String(text.prefix(8_000))
        }

        switch tool {
        case "github_list_prs":
            guard let state = state(arguments["state"] ?? "open") else {
                throw ToolError("state must be open, closed, merged, or all")
            }
            let json = try gh(["pr", "list", "--state", state, "--limit", "20",
                               "--json", "number,title,author,headRefName,url,isDraft"])
            return GitHubFormat.pullRequests(json: json)

        case "github_view_pr":
            let number = try requiredNumber()
            return capped(try gh(["pr", "view", number, "--json",
                                  "number,title,body,state,url,headRefName,baseRefName,additions,deletions,changedFiles,isDraft"]))

        case "github_pr_checks":
            let number = try requiredNumber()
            do {
                return capped(try gh(["pr", "checks", number]))
            } catch let error as ToolError {
                // gh exits with an error when a check failed, and its output is still the answer.
                return capped(error.message)
            }

        case "github_list_issues":
            guard let state = state(arguments["state"] ?? "open"), state != "merged" else {
                throw ToolError("state must be open, closed, or all")
            }
            let json = try gh(["issue", "list", "--state", state, "--limit", "20",
                               "--json", "number,title,state,url,author"])
            return GitHubFormat.issues(json: json)

        case "github_view_issue":
            let number = try requiredNumber()
            return capped(try gh(["issue", "view", number, "--json", "number,title,body,state,url,author"]))

        default:
            throw ToolError("unknown GitHub tool \(tool)")
        }
    }
}
#endif

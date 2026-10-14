//
//  CommandApproval.swift
//  Gatita
//

import Foundation

/// Asking before a command runs. Each command Gatita wants to run waits for your answer: Allow once, Always allow
/// (saved for this project), or Deny. "Always" is saved as the allowed command that matched, such as "swift test",
/// which then covers that command with any arguments, as Claude Code's "npm test *" rules do.
nonisolated enum CommandApproval {
    enum Decision: Sendable, Equatable {
        case allowOnce, allowAlways, deny
    }

    /// A command waiting for an answer, and the rule "Always allow" would save.
    struct Request: Sendable, Equatable {
        let command: String
        let rule: String
    }

    /// The allowed command a command matched, such as "swift test" for "swift test --filter Foo". Nil when the
    /// command is not allowed at all, which the tool itself then refuses.
    static func rule(for command: String, allowed: [[String]]) -> String? {
        guard let argv = CommandPolicy.allowed(command, allowed) else { return nil }
        return allowed.filter { argv.starts(with: $0) }.max { $0.count < $1.count }?.joined(separator: " ")
    }

    /// Whether a saved rule covers the command: the rule's words, then any arguments.
    static func covers(_ rules: [String], _ command: String) -> Bool {
        let words = command.split(separator: " ").map(String.init)
        return rules.contains { words.starts(with: $0.split(separator: " ").map(String.init)) }
    }

    static func rules(for project: String, in all: [String: [String]]) -> [String] {
        all[project] ?? []
    }

    /// The saved rules with one more for the project, kept once.
    static func adding(_ rule: String, project: String, to all: [String: [String]]) -> [String: [String]] {
        var all = all
        if !(all[project] ?? []).contains(rule) { all[project, default: []].append(rule) }
        return all
    }

    /// What to do without asking: allow, deny, or nil to ask. An MCP tool from a server you did not trust is always
    /// asked about (the "ask before each command" switch covers commands only). With `unattended` (a scheduled run,
    /// with nobody to answer) anything that would be asked is denied instead of waiting.
    static func decision(for request: Request, askBeforeCommands: Bool, rules: [String], trustedMCP: Bool,
                         unattended: Bool) -> Decision? {
        let isMCP = request.rule.hasPrefix("mcp__")
        if isMCP, trustedMCP { return .allowOnce }
        if covers(rules, request.command) { return .allowOnce }
        if !isMCP, !askBeforeCommands { return .allowOnce }
        return unattended ? .deny : nil
    }

    /// What the model is told when you deny a command.
    static func denial(_ command: String) -> String {
        "error: the user denied running \(command), so it did not run. Don't run it again unless they ask; tell them what you needed it for."
    }
}

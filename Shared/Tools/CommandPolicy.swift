//
//  CommandPolicy.swift
//  Gatita
//

import Foundation

/// Decides which command lines the model may run. Only plain commands that start with an allowed entry get through:
/// no shell syntax, no quoting, and nothing outside the list.
nonisolated enum CommandPolicy {
    /// Allowed out of the box. Plugins can add more.
    static let builtIn: [[String]] = [
        ["swift", "build"],
        ["swift", "test"],
        ["swift", "--version"],
        ["xcodebuild", "-version"],
        ["npm", "test"],
        ["npm", "run", "build"],
        ["python3", "-m", "pytest"],
    ]

    private static let forbidden: Set<Character> = [
        ";", "&", "|", "<", ">", "$", "`", "(", ")", "*", "?", "{", "}", "[", "]",
        "\\", "\"", "'", "\n", "\r", "#", "~",
    ]

    /// Splits a command line into arguments, or returns nil if it uses shell syntax.
    static func argv(_ line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.contains(where: { forbidden.contains($0) }) else { return nil }
        return trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
    }

    /// The arguments of `line` if it is plain and starts with one of the allowed entries.
    static func allowed(_ line: String, _ allowList: [[String]]) -> [String]? {
        guard let args = argv(line) else { return nil }
        let matches = allowList.contains { entry in
            args.count >= entry.count && Array(args.prefix(entry.count)) == entry
        }
        return matches ? args : nil
    }

    /// A macOS sandbox profile: no network, and file writes only inside the project and the usual build folders.
    static func sandboxProfile(projectRoot: String) -> String {
        let home = NSHomeDirectory()
        let writable = [projectRoot, "/private/tmp", "/private/var/folders", home + "/Library/Developer", home + "/Library/Caches"]
        let rules = writable.map { "    (subpath \"\(escape($0))\")" }.joined(separator: "\n")
        return """
        (version 1)
        (allow default)
        (deny network*)
        (deny file-write*)
        (allow file-write*
        \(rules)
            (literal "/dev/null"))
        """
    }

    private static func escape(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}

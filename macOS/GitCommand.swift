//
//  GitCommand.swift
//  Gatita
//

#if os(macOS)
import Foundation

/// Runs one read-only git command in a folder for `ProjectTools`, whose fixed commands are the only ones that reach
/// here, and returns what it printed, cut to `limit` characters.
nonisolated enum GitCommand {
    static func run(_ arguments: [String], in root: URL, limit: Int) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", root.path, "--no-pager"] + arguments
        process.environment = ProcessInfo.processInfo.environment.merging(["GIT_TERMINAL_PROMPT": "0"]) { _, new in new }
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            throw ToolError(text.isEmpty ? "git exited with status \(process.terminationStatus)" : text)
        }
        return text.isEmpty ? "(no output)" : String(text.prefix(limit))
    }
}
#endif

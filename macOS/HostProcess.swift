//
//  HostProcess.swift
//  Gatita
//

import Foundation

#if os(macOS)
/// Runs git and gh for the user's own actions, such as creating a pull request.
/// These run outside the model's sandbox, and only after the user presses the button and confirms.
nonisolated enum HostProcess {
    static func run(_ arguments: [String], in folder: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.currentDirectoryURL = folder

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GH_PROMPT_DISABLED"] = "1"
        process.environment = environment

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        // Trim only line breaks: git status lines start with a space that matters.
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines)
        guard process.terminationStatus == 0 else {
            throw ToolError("\(arguments.prefix(2).joined(separator: " ")) failed: \(text)")
        }
        return text
    }
}
#endif

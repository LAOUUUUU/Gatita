//
//  CommandRunner.swift
//  Gatita
//

import Foundation

#if os(macOS)
/// Runs one allowed command inside the macOS sandbox profile: in the project folder, with no network,
/// and a time limit. Output goes to a temporary file, so a chatty command cannot block on a full pipe.
nonisolated enum CommandRunner {
    static let timeout: TimeInterval = 120
    static let maxOutputCharacters = 20_000

    /// The sandboxed process for one command: the same profile, folder, and environment for every run.
    static func makeProcess(_ arguments: [String], in root: URL) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        process.arguments = ["-p", CommandPolicy.sandboxProfile(projectRoot: root.path), "/usr/bin/env"] + arguments
        process.currentDirectoryURL = root
        process.environment = [
            "PATH": "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": NSHomeDirectory(),
            "LANG": "en_US.UTF-8",
        ]
        return process
    }

    static func run(_ arguments: [String], in root: URL) throws -> String {
        let outputFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("gatita-cmd-\(UUID().uuidString).txt")
        FileManager.default.createFile(atPath: outputFile.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: outputFile) }
        let output = try FileHandle(forWritingTo: outputFile)

        let process = makeProcess(arguments, in: root)
        process.standardOutput = output
        process.standardError = output
        try process.run()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            try? output.close()
            throw ToolError("the command timed out after \(Int(timeout)) seconds")
        }
        process.waitUntilExit()
        try? output.close()

        let data = (try? Data(contentsOf: outputFile)) ?? Data()
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = String(text.prefix(maxOutputCharacters))
        if process.terminationStatus != 0 {
            throw ToolError("exit \(process.terminationStatus): \(shown)")
        }
        return shown.isEmpty ? "(no output)" : shown
    }
}
#endif

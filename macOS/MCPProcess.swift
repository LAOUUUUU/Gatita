//
//  MCPProcess.swift
//  Gatita
//

import Foundation
import System

#if os(macOS)
/// Starts a local MCP server: its command, found on the PATH your login shell uses (apps opened from the Dock get
/// a short one, without Homebrew or npm), with its stdin and stdout as the connection and its stderr discarded.
/// A server gets only a few basic variables from Gatita's environment, plus its own, so nothing Gatita was started
/// with (such as GATITA_API_KEY) reaches it, as the official TypeScript SDK does.
nonisolated enum MCPProcess {
    struct Started {
        let process: Process
        let input: FileDescriptor
        let output: FileDescriptor
    }

    /// The variables a server inherits from Gatita.
    static let inherited: Set<String> = ["HOME", "LOGNAME", "USER", "SHELL", "TERM", "TMPDIR", "LANG", "LC_ALL"]
    static let pathStart = "__GATITA_PATH_START__"
    static let pathEnd = "__GATITA_PATH_END__"

    static func start(_ server: MCPServerConfig) async throws -> Started {
        guard ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil else {
            throw MCPHub.Problem(message: "local MCP servers need App Sandbox off (the Debug build). Remote servers work in every build")
        }
        guard let command = server.command?.trimmingCharacters(in: .whitespaces), !command.isEmpty else {
            throw MCPHub.Problem(message: "the server has no command and no address")
        }
        let path = await loginPath.value
        let environment = environment(base: ProcessInfo.processInfo.environment, path: path, server: server.env)
        guard let executable = executable(command, path: environment["PATH"] ?? path) else {
            throw MCPHub.Problem(message: "\(command) was not found on your PATH")
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = server.args
        process.environment = environment
        let toServer = Pipe()
        let fromServer = Pipe()
        process.standardInput = toServer
        process.standardOutput = fromServer
        process.standardError = FileHandle.nullDevice
        try process.run()
        return Started(process: process,
                       input: FileDescriptor(rawValue: fromServer.fileHandleForReading.fileDescriptor),
                       output: FileDescriptor(rawValue: toServer.fileHandleForWriting.fileDescriptor))
    }

    /// What a server runs with: the basic variables from Gatita's environment, the login PATH, then its own.
    static func environment(base: [String: String], path: String, server: [String: String]) -> [String: String] {
        var environment = base.filter { inherited.contains($0.key) }
        environment["PATH"] = path
        for (key, value) in server { environment[key] = value }
        return environment
    }

    /// The command's file: a path as written, or the first match on the PATH.
    static func executable(_ command: String, path: String) -> URL? {
        if command.contains("/") {
            let url = URL(fileURLWithPath: (command as NSString).expandingTildeInPath)
            return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
        }
        for folder in path.split(separator: ":") {
            let url = URL(fileURLWithPath: String(folder)).appendingPathComponent(command)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }

    /// The PATH printed between the markers, ignoring anything else the shell printed as it started.
    static func path(fromShellOutput output: String) -> String? {
        guard let start = output.range(of: pathStart), let end = output.range(of: pathEnd, range: start.upperBound..<output.endIndex)
        else { return nil }
        let path = String(output[start.upperBound..<end.lowerBound])
        return path.isEmpty ? nil : path
    }

    /// The PATH of your login shell, worked out once, off the main thread, plus the usual places.
    static let loginPath = Task.detached(priority: .utility) { () -> String in
        let fallback = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
        shell.arguments = ["-l", "-c", "printf '%s%s%s' '\(pathStart)' \"$PATH\" '\(pathEnd)'"]
        let output = Pipe()
        shell.standardOutput = output
        shell.standardError = FileHandle.nullDevice
        guard (try? shell.run()) != nil else { return fallback }
        let deadline = Date().addingTimeInterval(5)
        while shell.isRunning, Date() < deadline { try? await Task.sleep(for: .milliseconds(50)) }
        if shell.isRunning {
            shell.terminate()
            return fallback
        }
        let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return path(fromShellOutput: text).map { $0 + ":" + fallback } ?? fallback
    }
}
#endif

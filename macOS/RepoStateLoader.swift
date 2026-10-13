//
//  RepoStateLoader.swift
//  Gatita
//

#if os(macOS)
import Foundation

/// Asks git about a folder: whether it is a repository, its worktrees, and which one the folder is in.
nonisolated enum RepoStateLoader {
    static let git = URL(fileURLWithPath: "/usr/bin/git")

    /// Runs off the main actor: git can take a while on a big repository, and the project bar calls this from a view.
    @concurrent
    static func load(for folder: URL, git: URL = RepoStateLoader.git) async -> RepoState {
        guard let top = await run(git, ["rev-parse", "--show-toplevel"], in: folder) else {
            return .notARepo
        }
        let topLevel = top.trimmingCharacters(in: .whitespacesAndNewlines)
        let listing = await run(git, ["worktree", "list", "--porcelain"], in: folder) ?? ""
        let trees = GitWorktrees.parse(listing)
        return RepoState(isRepo: true, worktrees: trees,
                         current: GitWorktrees.current(topLevel: topLevel, in: trees))
    }

    /// Runs git in a folder and returns its standard output, or nil when git fails or is missing.
    private static func run(_ git: URL, _ arguments: [String], in folder: URL) async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = git
            process.arguments = arguments
            process.currentDirectoryURL = folder
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
                return
            }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            continuation.resume(returning: process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil)
        }
    }
}
#endif

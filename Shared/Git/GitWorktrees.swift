//
//  GitWorktrees.swift
//  Gatita
//

import Foundation

/// One working tree of a git repository: a folder with its own checkout.
nonisolated struct GitWorktree: Equatable, Sendable, Identifiable {
    let path: String
    /// The branch checked out here, or nil when the tree has a detached HEAD.
    let branch: String?

    var id: String { path }

    /// The folder's own name, such as "Gatita" for /Users/you/Gatita.
    var name: String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

/// What the project bar needs to know about a folder under git.
nonisolated struct RepoState: Equatable, Sendable {
    let isRepo: Bool
    let worktrees: [GitWorktree]
    /// The worktree the project folder is in, found from the repository's top-level folder.
    let current: GitWorktree?

    static let notARepo = RepoState(isRepo: false, worktrees: [], current: nil)
}

nonisolated enum GitWorktrees {
    /// Reads `git worktree list --porcelain`. Each entry starts with a "worktree <path>" line.
    static func parse(_ porcelain: String) -> [GitWorktree] {
        var trees: [GitWorktree] = []
        var path: String?
        var branch: String?

        func finishEntry() {
            if let path {
                trees.append(GitWorktree(path: path, branch: branch))
            }
            path = nil
            branch = nil
        }

        for line in porcelain.components(separatedBy: "\n") {
            if line.hasPrefix("worktree ") {
                finishEntry()
                path = String(line.dropFirst("worktree ".count))
            } else if line.hasPrefix("branch refs/heads/") {
                branch = String(line.dropFirst("branch refs/heads/".count))
            }
        }
        finishEntry()
        return trees
    }

    /// The worktree whose path is the repository's top-level folder.
    static func current(topLevel: String, in worktrees: [GitWorktree]) -> GitWorktree? {
        let wanted = normalized(topLevel)
        return worktrees.first { normalized($0.path) == wanted }
    }

    /// Resolves symlinks and drops trailing slashes, so the same folder always compares equal.
    private static func normalized(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardized.path
    }
}

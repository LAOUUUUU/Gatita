//
//  Checkpoints.swift
//  Gatita
//

import Foundation

/// What a reply changed with write_file and edit_file, so it can be undone: each file as it was before the reply's
/// first change to it, and as the reply left it. Like Claude Code's checkpoints, changes made by commands are not
/// recorded. Kept in Application Support/Gatita/checkpoints/<reply id>.json for 30 days.
nonisolated struct Checkpoint: Codable, Equatable, Sendable {
    struct FileState: Codable, Equatable, Sendable {
        /// The file before the reply changed it, or nil when the reply made it.
        var original: String?
        /// The file after the reply's last change to it, or nil when it is gone.
        var latest: String?
    }

    let replyID: UUID
    /// The project folder the paths are in.
    let root: String
    /// Project-relative path to its states.
    var files: [String: FileState]
    var savedAt: Date
}

/// Records one reply's changes as they happen. `before` runs ahead of each write or edit, `after` once it worked.
@MainActor
final class CheckpointRecorder {
    let replyID: UUID
    let root: URL
    let directory: URL
    private(set) var checkpoint: Checkpoint

    /// `inheriting` are the checkpoints of replies this one replaces (regenerate and edit drop them): this reply
    /// takes over their changes, keeping each file's oldest original and newest text, so undoing it goes back to
    /// before them. Checkpoints of another project folder are left out.
    init(replyID: UUID, root: URL, directory: URL = CheckpointStore.defaultDirectory, inheriting: [Checkpoint] = []) {
        self.replyID = replyID
        self.root = root
        self.directory = directory
        checkpoint = Checkpoint(replyID: replyID, root: root.path, files: [:], savedAt: Date())
        for old in inheriting.filter({ $0.root == root.path }).sorted(by: { $0.savedAt < $1.savedAt }) {
            for (path, state) in old.files {
                checkpoint.files[path] = Checkpoint.FileState(original: checkpoint.files[path]?.original ?? state.original,
                                                              latest: state.latest)
            }
        }
        if !checkpoint.files.isEmpty { CheckpointStore.save(checkpoint, in: directory) }
    }

    /// Notes how the file is now, unless this reply already changed it. A file that is not UTF-8 text is not
    /// recorded, so undo leaves it alone.
    func before(_ path: String) {
        guard checkpoint.files[path] == nil, let url = CheckpointStore.inside(root, path),
              let now = CheckpointStore.contents(of: url) else { return }
        checkpoint.files[path] = Checkpoint.FileState(original: now.text, latest: now.text)
    }

    /// Notes how the change left the file, and saves the checkpoint.
    func after(_ path: String) {
        guard checkpoint.files[path] != nil, let url = CheckpointStore.inside(root, path) else { return }
        checkpoint.files[path]?.latest = CheckpointStore.contents(of: url)?.text
        checkpoint.savedAt = Date()
        CheckpointStore.save(checkpoint, in: directory)
    }
}

nonisolated enum CheckpointStore {
    static let keepDays = 30

    struct UndoResult: Equatable {
        let restored: [String]
        /// Files changed since the reply, which an undo without `force` leaves alone.
        let conflicts: [String]
    }

    static var defaultDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Gatita/checkpoints")
    }

    /// Puts each file back as it was before the reply, and removes the files it made. Without `force`, nothing
    /// changes when a file was changed again since the reply; the conflicts say which.
    static func undo(_ checkpoint: Checkpoint, force: Bool) -> UndoResult {
        let root = URL(fileURLWithPath: checkpoint.root)
        let paths = checkpoint.files.keys.sorted().filter { inside(root, $0) != nil }
        let conflicts = paths.filter { path in
            contents(of: inside(root, path)!)?.text != checkpoint.files[path]?.latest
        }
        guard force || conflicts.isEmpty else { return UndoResult(restored: [], conflicts: conflicts) }
        var restored: [String] = []
        for path in paths {
            guard let url = inside(root, path), let state = checkpoint.files[path] else { continue }
            if let original = state.original {
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard (try? original.write(to: url, atomically: true, encoding: .utf8)) != nil else { continue }
            } else if FileManager.default.fileExists(atPath: url.path) {
                guard (try? FileManager.default.removeItem(at: url)) != nil else { continue }
            }
            restored.append(path)
        }
        return UndoResult(restored: restored, conflicts: conflicts)
    }

    /// The file for a project-relative path, or nil when the path would leave the project, goes through a link
    /// to somewhere else, or is inside .git, as for the file tools.
    static func inside(_ root: URL, _ path: String) -> URL? {
        let parts = path.components(separatedBy: "/")
        guard !path.hasPrefix("/"), !parts.contains(".."), !parts.contains(".git") else { return nil }
        let base = root.standardizedFileURL.resolvingSymlinksInPath().path
        let url = root.appendingPathComponent(path).standardizedFileURL
        let real = url.resolvingSymlinksInPath()
        guard real.path.hasPrefix(base + "/") else { return nil }
        // A link inside the project is left alone too: writing would replace the link with a file.
        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { return nil }
        return real
    }

    /// A file as the checkpoint sees it: its text, or nil text when it does not exist.
    struct Contents {
        let text: String?
    }

    /// The file's contents. Nil when it exists but is not UTF-8 text, which checkpoints leave alone.
    static func contents(of url: URL) -> Contents? {
        guard FileManager.default.fileExists(atPath: url.path) else { return Contents(text: nil) }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return Contents(text: text)
    }

    static func save(_ checkpoint: Checkpoint, in directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(checkpoint) {
            try? data.write(to: file(checkpoint.replyID, in: directory), options: .atomic)
        }
    }

    static func load(_ replyID: UUID, in directory: URL) -> Checkpoint? {
        guard let data = try? Data(contentsOf: file(replyID, in: directory)) else { return nil }
        return try? JSONDecoder().decode(Checkpoint.self, from: data)
    }

    static func remove(_ replyID: UUID, in directory: URL) {
        try? FileManager.default.removeItem(at: file(replyID, in: directory))
    }

    /// The replies that have a checkpoint.
    static func replyIDs(in directory: URL) -> Set<UUID> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return Set(names.filter { $0.hasSuffix(".json") }.compactMap { UUID(uuidString: String($0.dropLast(5))) })
    }

    /// Deletes checkpoints older than `keepDays`.
    static func removeOld(in directory: URL, now: Date) {
        for id in replyIDs(in: directory) {
            guard let checkpoint = load(id, in: directory),
                  now.timeIntervalSince(checkpoint.savedAt) > Double(keepDays) * 86_400 else { continue }
            remove(id, in: directory)
        }
    }

    private static func file(_ replyID: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent(replyID.uuidString + ".json")
    }
}

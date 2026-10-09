//
//  ProjectTools.swift
//  Gatita
//

import Foundation

/// File tools the model can call. Every path is confined to `root`, `.git` is
/// off limits, and writes stay disabled unless `allowWrites` is set.
nonisolated struct ProjectTools: Sendable {
    static let maxReadCharacters = 100_000
    static let maxListEntries = 500
    static let maxListDepth = 4
    static let maxSearchHits = 200

    /// The project folder. Nil on hosts without one, where every file tool and command is refused.
    let root: URL?
    let allowWrites: Bool
    let allowCommands: Bool
    let commands: [[String]]
    let logDirectory: URL?
    /// Connectors whose tools are on for this set of tools.
    let connectors: Set<String>
    /// Whether this set of tools can start subagents. A subagent's own tools cannot.
    let allowsSubagents: Bool

    init(root: URL?,
         allowWrites: Bool,
         allowCommands: Bool = false,
         commands: [[String]] = CommandPolicy.builtIn,
         logDirectory: URL? = nil,
         connectors: Set<String> = [],
         allowsSubagents: Bool = true) {
        self.root = root?.standardizedFileURL.resolvingSymlinksInPath()
        self.allowWrites = allowWrites
        self.allowCommands = allowCommands
        self.commands = commands
        self.logDirectory = logDirectory
        self.connectors = connectors
        self.allowsSubagents = allowsSubagents
    }

    /// Background commands need a project folder and running commands turned on.
    var allowsBackground: Bool {
        root != nil && allowCommands
    }

    /// The same project for a subagent: read-only, with no commands, and no subagents of its own.
    func readOnlyForSubagents() -> ProjectTools {
        ProjectTools(root: root, allowWrites: false, allowCommands: false, commands: commands,
                     logDirectory: logDirectory, connectors: connectors, allowsSubagents: false)
    }

    /// Reads GATITA_PROJECT_ROOT (set GATITA_ALLOW_WRITES=1 to allow edits).
    /// Returns nil when no project root is set, which leaves the chat without tools.
    static func fromEnvironment() -> ProjectTools? {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["GATITA_PROJECT_ROOT"], !path.isEmpty else { return nil }
        return ProjectTools(
            root: URL(fileURLWithPath: (path as NSString).expandingTildeInPath),
            allowWrites: env["GATITA_ALLOW_WRITES"] == "1")
    }

    /// System message that explains the <gatita-tool> block format and the tools on offer.
    /// Hosts without a project folder are told only about the tools they can run.
    var instructions: String {
        let hasFolder = root != nil
        var lines = [
            "You can use tools by writing tool blocks. To call a tool, write exactly one block in this form, then stop:",
            hasFolder
                ? "<gatita-tool>{\"tool\": \"list_files\", \"path\": \".\"}</gatita-tool>"
                : "<gatita-tool>{\"tool\": \"list_reports\"}</gatita-tool>",
            "The result comes back in your next message inside <gatita-tool-result> tags. Never invent results. When you have what you need, answer normally without tool blocks.",
            "If a tool or a reply fails, call list_reports, then read_report on the newest failure, before trying a fix.",
            "",
            "Tools:",
        ]
        if hasFolder {
            lines += [
                "- list_files: {\"tool\": \"list_files\", \"path\": \"<folder, or . for the project root>\"} lists files and folders up to 4 levels deep.",
                "- read_file: {\"tool\": \"read_file\", \"path\": \"<file>\"} reads a text file.",
                "- search_text: {\"tool\": \"search_text\", \"query\": \"<text>\"} finds lines containing the text, as path:line:text, up to 200 hits.",
                "- git_status: {\"tool\": \"git_status\"} lists changed files in the project's git repository.",
                "- git_diff: {\"tool\": \"git_diff\", \"path\": \"<optional file>\"} shows uncommitted changes.",
            ]
        }
        lines += [
            "- list_reports: {\"tool\": \"list_reports\"} lists failure reports and the app log.",
            "- read_report: {\"tool\": \"read_report\", \"name\": \"<a name from list_reports>\"} reads one failure report or the log.",
            "- ask_user: {\"tool\": \"ask_user\", \"question\": \"<question>\"} asks the user something you need. Make it the last thing in your reply, then wait for their answer.",
        ]
        #if os(macOS)
        if hasFolder {
            lines.append("- web_check: {\"tool\": \"web_check\", \"path\": \"<html file>\"} loads a local page at phone and desktop widths and reports layout and content problems.")
        }
        #endif
        for connector in Connectors.catalog where connectors.contains(connector.id) {
            lines.append(contentsOf: Connectors.toolHelp(for: connector))
        }
        if hasFolder {
            let allowedList = commands.map { $0.joined(separator: " ") }.joined(separator: ", ")
            if allowCommands {
                lines.append("- run_command: {\"tool\": \"run_command\", \"command\": \"<command>\"} runs one allowed command in the project, with no network and writes only inside the project. Allowed: \(allowedList).")
            }
            if allowsBackground {
                lines.append("- run_background: {\"tool\": \"run_background\", \"command\": \"<command>\"} starts one allowed command in the background. It keeps running after this reply. Allowed: \(allowedList).")
                lines.append("- task_status: {\"tool\": \"task_status\", \"id\": \"<task id>\"} shows whether a background task is running, its exit code, and its latest output.")
                lines.append("- task_stop: {\"tool\": \"task_stop\", \"id\": \"<task id>\"} stops a running background task.")
            }
            if allowsSubagents {
                lines.append("- spawn_agent: {\"tool\": \"spawn_agent\", \"task\": \"<task>\"} starts a subagent on one task. It reads the project but cannot edit files or run commands. It runs alongside you, so you can start several and keep working.")
                lines.append("- agent_result: {\"tool\": \"agent_result\", \"id\": \"<subagent id>\"} waits for a subagent and returns its answer.")
            }
            if allowWrites {
                lines.append("- write_file: {\"tool\": \"write_file\", \"path\": \"<file>\", \"content\": \"<full file content>\"} creates or overwrites a file.")
                lines.append("- edit_file: {\"tool\": \"edit_file\", \"path\": \"<file>\", \"old_text\": \"<exact text>\", \"new_text\": \"<replacement>\"} replaces one exact occurrence; old_text must appear exactly once.")
            } else {
                lines.append("Writing files is turned off, so do not call write_file or edit_file.")
            }
            lines.append("Paths are relative to the project root. Do not use absolute paths or touch .git.")
        }
        return lines.joined(separator: "\n")
    }

    /// Runs one tool call. Errors come back as "error: ..." text so the model can react to them.
    func run(name: String, arguments: String) -> String {
        do {
            let args = try JSONDecoder().decode([String: String].self, from: Data(arguments.utf8))
            switch name {
            case "list_files":
                return try listFiles(try required(args, "path"))
            case "read_file":
                return try readFile(try required(args, "path"))
            case "write_file":
                return try writeFile(path: try required(args, "path"), content: try required(args, "content"))
            case "run_command":
                guard allowCommands else {
                    throw ToolError("running commands is turned off. Turn on \"Let Gatita run commands\" in Settings.")
                }
                guard let argv = CommandPolicy.allowed(try required(args, "command"), commands) else {
                    throw ToolError("that command is not on the allowed list, or it uses shell syntax")
                }
                return try runCommand(argv)
            case "list_reports":
                return try listReports()
            case "read_report":
                return try readReport(try required(args, "name"))
            case "ask_user":
                return "the question was sent to the user; wait for their answer."
            case "search_text":
                return try searchText(try required(args, "query"))
            case "git_status":
                return try git(["status", "--short", "--branch"])
            case "git_diff":
                if let path = args["path"] {
                    _ = try resolve(path)
                    return try git(["diff", "--", path])
                }
                return try git(["diff"])
            case "edit_file":
                return try editFile(path: try required(args, "path"),
                                    oldText: try required(args, "old_text"),
                                    newText: try required(args, "new_text"))
            default:
                return "error: unknown tool \(name)"
            }
        } catch {
            return "error: \(error.localizedDescription)"
        }
    }

    // MARK: - Tools

    private func listFiles(_ relative: String) throws -> String {
        let root = try folder()
        let base = try resolve(relative)
        guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isDirectoryKey]) else {
            throw ToolError("cannot list \(relative)")
        }
        let rootPrefixLength = root.path.count + 1
        var lines: [String] = []
        for case let url as URL in walker {
            let name = url.lastPathComponent
            if name == ".git" {
                walker.skipDescendants()
                continue
            }
            if name == ".DS_Store" { continue }
            if url.pathComponents.count - base.pathComponents.count > Self.maxListDepth {
                walker.skipDescendants()
                continue
            }
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let relativePath = String(url.path.dropFirst(rootPrefixLength))
            lines.append(isDirectory ? relativePath + "/" : relativePath)
            if lines.count >= Self.maxListEntries {
                lines.append("... truncated at \(Self.maxListEntries) entries")
                break
            }
        }
        return lines.isEmpty ? "(empty)" : lines.joined(separator: "\n")
    }

    private func readFile(_ relative: String) throws -> String {
        let url = try resolve(relative)
        guard isRegularFile(url) else { throw ToolError("not a file: \(relative)") }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ToolError("not a UTF-8 text file: \(relative)")
        }
        guard text.count > Self.maxReadCharacters else { return text }
        return String(text.prefix(Self.maxReadCharacters)) + "\n... truncated at \(Self.maxReadCharacters) characters"
    }

    private func writeFile(path: String, content: String) throws -> String {
        try requireWrites()
        let url = try resolve(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return "wrote \(path)"
    }

    private func editFile(path: String, oldText: String, newText: String) throws -> String {
        try requireWrites()
        let url = try resolve(path)
        guard isRegularFile(url) else { throw ToolError("not a file: \(path)") }
        let text = try String(contentsOf: url, encoding: .utf8)
        let occurrences = text.components(separatedBy: oldText).count - 1
        guard occurrences == 1 else {
            throw ToolError("old_text found \(occurrences) times in \(path); it must appear exactly once")
        }
        try text.replacingOccurrences(of: oldText, with: newText).write(to: url, atomically: true, encoding: .utf8)
        return "edited \(path)"
    }

    // MARK: - Helpers

    /// The project as a tree for the file list. Folders come before files, and .git is left out.
    func tree() throws -> [FileNode] {
        try nodes(in: try folder(), relativeTo: "", depth: 1)
    }

    /// Text of one project file, for showing in the app. Same path rules as read_file.
    func readText(_ relative: String) throws -> String {
        try readFile(relative)
    }

    private func nodes(in folder: URL, relativeTo parent: String, depth: Int) throws -> [FileNode] {
        let entries = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey])
        let items = entries
            .filter { $0.lastPathComponent != ".git" && $0.lastPathComponent != ".DS_Store" }
            .map { url -> (url: URL, isDirectory: Bool) in
                (url, (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false)
            }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent) == .orderedAscending
            }

        return try items.map { item in
            let name = item.url.lastPathComponent
            let path = parent.isEmpty ? name : parent + "/" + name
            guard item.isDirectory else {
                return FileNode(path: path, name: name, isDirectory: false, children: nil)
            }
            let children = depth < Self.maxListDepth
                ? try nodes(in: item.url, relativeTo: path, depth: depth + 1)
                : []
            return FileNode(path: path, name: name, isDirectory: true, children: children)
        }
    }

    private func searchText(_ query: String) throws -> String {
        guard !query.isEmpty else { throw ToolError("query is empty") }
        var hits: [String] = []
        try searchFolder(try folder(), relativeTo: "", query: query, hits: &hits)
        return hits.isEmpty ? "(no matches)" : hits.joined(separator: "\n")
    }

    private func searchFolder(_ folder: URL, relativeTo parent: String, query: String, hits: inout [String]) throws {
        let entries = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey])
        for url in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = url.lastPathComponent
            guard name != ".git", name != ".DS_Store", hits.count < Self.maxSearchHits else { continue }
            let path = parent.isEmpty ? name : parent + "/" + name
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                try searchFolder(url, relativeTo: path, query: query, hits: &hits)
            } else if let text = try? String(contentsOf: url, encoding: .utf8) {
                for (number, line) in text.components(separatedBy: "\n").enumerated() where line.contains(query) {
                    hits.append("\(path):\(number + 1):\(line)")
                    if hits.count >= Self.maxSearchHits { break }
                }
            }
        }
    }

#if os(macOS)
    /// Runs one read-only git command in the project folder. Only the fixed commands above reach here.
    private func git(_ arguments: [String]) throws -> String {
        let root = try folder()
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
        return text.isEmpty ? "(no output)" : String(text.prefix(Self.maxReadCharacters))
    }
#else
    private func git(_ arguments: [String]) throws -> String {
        throw ToolError("git tools are only available on the Mac host")
    }
#endif

    /// The change a write or edit would make, for the diff in the chat. Nothing is written. Nil for other tools,
    /// and for an edit that would fail.
    func changePreview(name: String, arguments: String) -> FileChange? {
        guard let args = try? JSONDecoder().decode([String: String].self, from: Data(arguments.utf8)),
              let path = args["path"] else { return nil }
        let current = (try? readText(path)) ?? ""
        switch name {
        case "write_file":
            guard let content = args["content"] else { return nil }
            return FileChange(path: path, lines: LineDiff.lines(from: current, to: content))
        case "edit_file":
            guard let oldText = args["old_text"], let newText = args["new_text"],
                  current.components(separatedBy: oldText).count - 1 == 1 else { return nil }
            let updated = current.replacingOccurrences(of: oldText, with: newText)
            return FileChange(path: path, lines: LineDiff.lines(from: current, to: updated))
        default:
            return nil
        }
    }

    /// Runs one tool call. The web check needs the main actor, so it is awaited here; everything else runs inline.
    func execute(name: String, arguments: String) async -> String {
        if let connector = Connectors.connector(for: name) {
            guard connectors.contains(connector.id) else {
                return "error: the \(connector.name) connector is turned off. Mention !\(connector.id) in a message, or turn it on in Settings."
            }
            do {
                return try await Connectors.run(name, arguments: Connectors.stringArguments(arguments), root: root)
            } catch {
                return "error: \(error.localizedDescription)"
            }
        }
        #if os(macOS)
        if name == "web_check" {
            do {
                let args = try JSONDecoder().decode([String: String].self, from: Data(arguments.utf8))
                let file = try resolve(try required(args, "path"))
                return try await WebCheck.check(file: file, root: try folder())
            } catch {
                return "error: \(error.localizedDescription)"
            }
        }
        #endif
        return run(name: name, arguments: arguments)
    }

    private func listReports() throws -> String {
        guard let logDirectory else { throw ToolError("no log folder is set") }
        let folder = logDirectory.appendingPathComponent("failures", isDirectory: true)
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted(by: >)
        var lines = names.prefix(50).map { "failures/\($0)" }
        if FileManager.default.fileExists(atPath: logDirectory.appendingPathComponent("gatita.log").path) {
            lines.append("gatita.log")
        }
        return lines.isEmpty ? "(no reports)" : lines.joined(separator: "\n")
    }

    private func readReport(_ name: String) throws -> String {
        guard let logDirectory else { throw ToolError("no log folder is set") }
        let isLog = name == "gatita.log"
        let isReport = name.hasPrefix("failures/") && !name.contains("..")
        guard isLog || isReport else { throw ToolError("only gatita.log and failures/ reports can be read") }
        guard let text = try? String(contentsOf: logDirectory.appendingPathComponent(name), encoding: .utf8) else {
            throw ToolError("cannot read \(name)")
        }
        return String(text.suffix(Self.maxReadCharacters))
    }

    private func runCommand(_ arguments: [String]) throws -> String {
        #if os(macOS)
        return try CommandRunner.run(arguments, in: try folder())
        #else
        throw ToolError("commands can only run on the Mac host")
        #endif
    }

    /// Turns a model-supplied relative path into a URL inside the project, or throws.
    func resolve(_ relative: String) throws -> URL {
        let root = try folder()
        guard !relative.hasPrefix("/") else { throw ToolError("path must be relative to the project: \(relative)") }
        let url = root.appendingPathComponent(relative).standardizedFileURL.resolvingSymlinksInPath()
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard url == root || url.path.hasPrefix(prefix) else {
            throw ToolError("path is outside the project: \(relative)")
        }
        guard !url.pathComponents.contains(".git") else { throw ToolError("refusing to touch .git") }
        return url
    }

    private func required(_ args: [String: String], _ key: String) throws -> String {
        guard let value = args[key] else { throw ToolError("missing argument \(key)") }
        return value
    }

    /// The project folder, or an error on a host that has none.
    private func folder() throws -> URL {
        guard let root else { throw ToolError("project files are only available on the Mac host") }
        return root
    }

    private func requireWrites() throws {
        guard allowWrites else {
            throw ToolError("writes are disabled; set GATITA_ALLOW_WRITES=1 on the host to allow edits")
        }
    }

    private func isRegularFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }
}

nonisolated struct ToolError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

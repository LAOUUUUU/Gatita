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
    /// The most files find_files and the same-name suggestions look at, so a huge folder stays quick.
    static let maxScannedFiles = 30_000
    /// Folders find_files and the same-name suggestions skip: version control and build output.
    private static let skippedFolders: Set<String> = [".git", "node_modules", ".build", "DerivedData", "build", "Pods", ".venv", "__pycache__"]

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
    /// Whether the failure-report tools and the question tool are offered. Off for a Mac chat.
    let allowsReports: Bool
    /// Where Gatita's memory is kept, which turns on remember, forget, and list_memories. Nil when memory is off.
    let memoryFile: URL?
    /// More tool lines, from MCP servers (`MCPHub.toolHelp`). Their calls are run by the client, not here.
    let extraToolHelp: [String]

    init(root: URL?,
         allowWrites: Bool,
         allowCommands: Bool = false,
         commands: [[String]] = CommandPolicy.builtIn,
         logDirectory: URL? = nil,
         connectors: Set<String> = [],
         allowsSubagents: Bool = true,
         allowsReports: Bool = true,
         memoryFile: URL? = nil,
         extraToolHelp: [String] = []) {
        self.root = root?.standardizedFileURL.resolvingSymlinksInPath()
        self.allowWrites = allowWrites
        self.allowCommands = allowCommands
        self.commands = commands
        self.logDirectory = logDirectory
        self.connectors = connectors
        self.allowsSubagents = allowsSubagents
        self.allowsReports = allowsReports
        self.memoryFile = memoryFile
        self.extraToolHelp = extraToolHelp
    }

    /// Background commands need a project folder and running commands turned on.
    var allowsBackground: Bool {
        root != nil && allowCommands
    }

    /// The same project for a subagent: read-only, with no commands, and no subagents of its own.
    func readOnlyForSubagents() -> ProjectTools {
        ProjectTools(root: root, allowWrites: false, allowCommands: false, commands: commands,
                     logDirectory: logDirectory, connectors: connectors, allowsSubagents: false,
                     allowsReports: allowsReports)
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
                : allowsReports
                    ? "<gatita-tool>{\"tool\": \"list_reports\"}</gatita-tool>"
                    : connectors.isEmpty && memoryFile != nil
                        ? "<gatita-tool>{\"tool\": \"list_memories\"}</gatita-tool>"
                        : "<gatita-tool>{\"tool\": \"web_fetch\", \"url\": \"https://example.com\"}</gatita-tool>",
            "The result comes back in your next message inside <gatita-tool-result> tags. Never invent results. When you have what you need, answer normally without tool blocks.",
            "After each result, either call the next tool or answer the user. Never end a message with nothing, or with a colon and no tool block.",
        ]
        if allowsReports {
            lines.append("If a tool or a reply fails, call list_reports, then read_report on the newest failure, before trying a fix.")
        }
        lines.append("")
        lines.append("Tools:")
        lines.append(#"- batch: {"tool": "batch", "calls": [{"tool": "<first tool>", ...}, {"tool": "<second tool>", ...}]} runs up to \#(ToolBatch.maxCalls) tool calls in one step and returns all their results, each between start and end lines. Use it whenever you need several calls that do not depend on each other's results."#)
        if hasFolder {
            lines += [
                "- list_files: {\"tool\": \"list_files\", \"path\": \"<folder, or . for the project root>\"} lists files and folders up to 4 levels deep.",
                "- read_file: {\"tool\": \"read_file\", \"path\": \"<file>\"} reads a text file.",
                "- read_files: {\"tool\": \"read_files\", \"paths\": \"<paths, folders, or patterns such as Shared/**/*.swift, one per line>\"} reads up to \(ReadFiles.maxFiles) files at once and returns them as one Markdown document; each file sits between a \"===== start of <path> =====\" line and an \"===== end of <path> =====\" line. A folder reads every text file under it. Use it instead of several read_file calls.",
                "- find_files: {\"tool\": \"find_files\", \"name\": \"<part of a file name>\"} lists the files whose name contains the text, in any case. Use it to find a file instead of guessing its path.",
                "- search_text: {\"tool\": \"search_text\", \"query\": \"<text>\", \"path\": \"<folder, optional>\", \"ignore_case\": true} finds lines containing the text, as path:line:text, up to 200 hits. path and ignore_case are optional.",
                "- git_status: {\"tool\": \"git_status\"} lists changed files in the project's git repository.",
                "- git_diff: {\"tool\": \"git_diff\", \"path\": \"<optional file>\"} shows uncommitted changes.",
            ]
        }
        if allowsReports {
            lines += [
                "- list_reports: {\"tool\": \"list_reports\"} lists failure reports and the app log.",
                "- read_report: {\"tool\": \"read_report\", \"name\": \"<a name from list_reports>\"} reads one failure report or the log.",
                "- ask_user: {\"tool\": \"ask_user\", \"question\": \"<question>\"} asks the user something you need. Make it the last thing in your reply, then wait for their answer.",
            ]
        }
        if memoryFile != nil {
            lines += [
                "- remember: {\"tool\": \"remember\", \"fact\": \"<one short fact about the user>\"} saves a fact for future chats. Use it when the user tells you something lasting about themselves (their name, preferences, projects, how they like answers), or asks you to remember something. Never save passwords, keys, or other secrets.",
                "- forget: {\"tool\": \"forget\", \"fact\": \"<words from the fact>\"} removes a saved fact, when the user asks you to forget it or it is no longer true.",
                "- list_memories: {\"tool\": \"list_memories\"} lists everything you remember about the user.",
            ]
        }
        #if os(macOS)
        if hasFolder {
            lines.append("- web_check: {\"tool\": \"web_check\", \"path\": \"<html file>\"} loads a local page at phone and desktop widths and reports layout and content problems.")
        }
        #endif
        for connector in Connectors.catalog where connectors.contains(connector.id) {
            lines.append(contentsOf: Connectors.toolHelp(for: connector))
        }
        lines += extraToolHelp
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

    /// The names of the tools on offer, read from the instructions so the two always agree.
    var toolNames: [String] {
        let pattern = try? NSRegularExpression(pattern: #""tool": "([A-Za-z0-9_.-]+)""#)
        return instructions.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }.compactMap { line in
            let range = NSRange(line.startIndex..., in: line)
            guard let match = pattern?.firstMatch(in: line, range: range),
                  let name = Range(match.range(at: 1), in: line) else { return nil }
            return String(line[name])
        }
    }

    private var toolList: String {
        toolNames.joined(separator: ", ")
    }

    /// Runs one tool call. Errors come back as "error: ..." text so the model can react to them.
    func run(name: String, arguments: String) -> String {
        do {
            guard let args = ToolArguments.parse(arguments) else {
                throw ToolError(#"the tool block is not valid JSON, so nothing ran. Write one JSON object with double quotes, and \n for each line break inside a text, such as {"tool": "read_file", "path": "README.md"}"#)
            }
            switch name {
            case "list_files":
                return try listFiles(try required(args, "path"))
            case "read_file":
                return try readFile(try required(args, "path"))
            case "read_files":
                return try readFiles(try required(args, "paths"))
            case "write_file":
                return try writeFile(path: try required(args, "path"), content: try required(args, "content"))
            case "run_command":
                guard allowCommands else {
                    throw ToolError("running commands is turned off. Turn on \"Let Gatita run commands\" in Settings.")
                }
                let command = try required(args, "command")
                guard let argv = CommandPolicy.allowed(command, commands) else {
                    let allowed = commands.map { $0.joined(separator: " ") }.joined(separator: ", ")
                    throw ToolError("\(command) is not on the allowed list, or it uses shell syntax (pipes, quotes, redirects). Allowed commands, each with any plain arguments after it: \(allowed)")
                }
                return try runCommand(argv)
            case "list_reports" where allowsReports:
                return try listReports()
            case "read_report" where allowsReports:
                return try readReport(try required(args, "name"))
            case "ask_user" where allowsReports:
                return "the question was sent to the user; wait for their answer."
            case "search_text":
                return try searchText(try required(args, "query"), in: args["path"],
                                      ignoreCase: args["ignore_case"] == "true")
            case "find_files":
                let found = try findFiles(named: try required(args, "name"))
                return found.isEmpty ? "(no matches)" : found.joined(separator: "\n")
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
            case "remember", "forget", "list_memories":
                return try memory(name, args)
            default:
                // The client names a block with no "tool" field "unknown".
                if name == "unknown", args["tool"] == nil {
                    return #"error: the tool block has no "tool" field, so nothing ran. Name the tool, such as {"tool": "read_file", "path": "README.md"}. Tools you can use here: "# + toolList
                }
                return "error: unknown tool \(name). Tools you can use here: \(toolList)"
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

    /// The memory tools. Each reads the file, changes it, and writes it back.
    private func memory(_ name: String, _ args: [String: String]) throws -> String {
        guard let file = memoryFile else {
            throw ToolError("memory is turned off. The user can turn it on in Settings, Memory.")
        }
        let facts = MemoryStore.load(from: file)
        switch name {
        case "remember":
            let fact = try required(args, "fact")
            let after = try MemoryStore.remember(fact, in: facts, at: Date()).get()
            guard after.count > facts.count else { return "already remembered: \(fact)" }
            MemoryStore.save(after, to: file)
            return "remembered: \(after.last?.text ?? fact)"
        case "forget":
            let words = try required(args, "fact")
            let after = try MemoryStore.forget(words, in: facts).get()
            MemoryStore.save(after, to: file)
            let gone = facts.filter { fact in !after.contains(fact) }.map(\.text)
            return "forgot: \(gone.joined(separator: "; "))"
        default:
            guard !facts.isEmpty else { return "You remember nothing about the user yet." }
            return "You remember \(facts.count) facts:\n" + facts.map { "- \($0.text)" }.joined(separator: "\n")
        }
    }

    private func readFile(_ relative: String) throws -> String {
        let url = try resolve(relative)
        guard isRegularFile(url) else { throw ToolError(notAFile(relative, at: url)) }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ToolError("not a UTF-8 text file: \(relative)")
        }
        guard text.count > Self.maxReadCharacters else { return text }
        return String(text.prefix(Self.maxReadCharacters)) + "\n... truncated at \(Self.maxReadCharacters) characters"
    }

    /// Reads several files and returns them as one Markdown document. An entry can be a path, a folder (every file
    /// under it), or a pattern such as "Shared/**/*.swift". A file that can't be read gets its reason in place of its
    /// text, and the others are still read; a file a folder or pattern found that is not text is skipped quietly.
    /// The text of all files together is capped.
    private func readFiles(_ list: String) throws -> String {
        let entries = ReadFiles.pathList(list)
        guard !entries.isEmpty else { throw ToolError("give at least one path in paths") }

        var paths: [String] = []          // in the order they will be read
        var found = Set<String>()         // paths a folder or pattern found
        var sections: [String] = []       // notes about entries that found nothing
        var explicit = 0
        for entry in entries {
            if let pattern = try expansion(of: entry) {
                guard ReadFiles.isValidPattern(pattern) else {
                    sections.append(ReadFiles.section(path: entry, note: "error: \(entry) is not a valid pattern. Use * and ? inside one folder, ** across folders, and a closed [abc] for one of a set."))
                    continue
                }
                let matches = try filesMatching(pattern)
                if matches.isEmpty {
                    sections.append(ReadFiles.section(path: entry, note: "no files match"))
                }
                for match in matches where !paths.contains(match) {
                    paths.append(match)
                    found.insert(match)
                }
            } else {
                explicit += 1
                paths.append(entry)
            }
        }
        guard explicit <= ReadFiles.maxFiles else {
            throw ToolError("\(explicit) files is too many. Read at most \(ReadFiles.maxFiles) at a time.")
        }

        var seen = Set<URL>()
        var distinct = 0
        var read = 0
        var notText: [String] = []
        var left = 0
        var remaining = ReadFiles.maxCharacters
        for path in paths {
            let url: URL
            do {
                url = try resolve(path)
            } catch {
                distinct += 1
                sections.append(ReadFiles.section(path: path, note: "error: \(error.localizedDescription)"))
                continue
            }
            guard seen.insert(url).inserted else { continue } // the same file under another spelling
            if found.contains(path), !isText(url) {
                notText.append(path)
                continue
            }
            guard distinct < ReadFiles.maxFiles else {
                left += 1
                continue
            }
            distinct += 1
            guard remaining > 0 else {
                sections.append(ReadFiles.section(path: path, note: "skipped: the \(ReadFiles.maxCharacters)-character limit for one read_files call was reached. Read it on its own."))
                continue
            }
            do {
                var text = try readFile(path)
                var cut = false
                if text.count > remaining {
                    text = String(text.prefix(remaining))
                    cut = true
                }
                remaining -= text.count
                read += 1
                var section = ReadFiles.section(path: path, text: text)
                if cut {
                    section += "\n\ntruncated: the \(ReadFiles.maxCharacters)-character limit for one read_files call was reached."
                }
                sections.append(section)
            } catch {
                sections.append(ReadFiles.section(path: path, note: "error: \(error.localizedDescription)"))
            }
        }
        if left > 0 {
            sections.append("\(left) more files matched and were not read, since one call reads at most \(ReadFiles.maxFiles). Read them in another call.")
        }
        if !notText.isEmpty {
            let noun = notText.count == 1 ? "file that is" : "files that are"
            sections.append("Skipped \(notText.count) \(noun) not text: \(notText.prefix(10).joined(separator: ", "))")
        }
        return (["Read \(read) of \(distinct) files."] + sections).joined(separator: "\n\n")
    }

    /// The pattern an entry stands for: "folder/**" when it is a folder, itself when it is a pattern, or nil for a
    /// plain path. A path that exists is never a pattern, even with [ or ? in its name (web/[id]/page.tsx).
    /// A pattern may not leave the project.
    private func expansion(of entry: String) throws -> String? {
        var isDirectory: ObjCBool = false
        if let url = try? resolve(entry), FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { return nil }
            let relative = url == (try folder()) ? "" : String(url.path.dropFirst(try folder().path.count + 1))
            return relative.isEmpty ? "**" : ReadFiles.escaped(relative) + "/**"
        }
        guard ReadFiles.isPattern(entry) else { return nil }
        guard !entry.hasPrefix("/"), !entry.components(separatedBy: "/").contains("..") else {
            throw ToolError("the pattern \(entry) leaves the project; patterns are relative to the project root")
        }
        return entry.hasPrefix("./") ? String(entry.dropFirst(2)) : entry
    }

    /// Project files whose path matches the pattern, sorted. Version control and build folders are skipped, and,
    /// as in a shell, hidden files and folders (such as .env) are found only by a pattern that names one itself.
    private func filesMatching(_ pattern: String) throws -> [String] {
        guard let walker = FileManager.default.enumerator(atPath: try folder().path) else { return [] }
        let findsHidden = pattern.hasPrefix(".") || pattern.contains("/.")
        var found: [String] = []
        var scanned = 0
        while let path = walker.nextObject() as? String {
            let name = (path as NSString).lastPathComponent
            let isFolder = walker.fileAttributes?[.type] as? FileAttributeType == .typeDirectory
            if Self.skippedFolders.contains(name) || (!findsHidden && name.hasPrefix(".")) {
                if isFolder { walker.skipDescendants() }
                continue
            }
            if isFolder { continue }
            scanned += 1
            if scanned > Self.maxScannedFiles { break }
            if ReadFiles.matches(path, pattern: pattern) { found.append(path) }
        }
        return found.sorted()
    }

    /// Whether a file's first bytes decode as UTF-8 text with no NUL bytes.
    private func isText(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 4096)) ?? Data()
        if head.contains(0) { return false }
        // A cut in the middle of a multi-byte character is not a reason to call the file binary.
        for drop in 0...3 where head.count >= drop {
            if String(data: head.dropLast(drop), encoding: .utf8) != nil { return true }
        }
        return false
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

    /// Why a path can't be read as a file: it is a folder, or it does not exist. A missing file's name is looked up
    /// in the rest of the project, so the model learns where it really is.
    private func notAFile(_ relative: String, at url: URL) -> String {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return "not a file: \(relative) is a folder. Use list_files to see what is in it."
        }
        let name = url.lastPathComponent
        let sameName = ((try? findFiles(named: name)) ?? []).filter { ($0 as NSString).lastPathComponent == name }
        guard !sameName.isEmpty else { return "not a file: \(relative). Use find_files to look for it." }
        return "not a file: \(relative). Files with that name: \(sameName.prefix(5).joined(separator: ", "))"
    }

    /// Project files whose name contains the text, in any case, sorted by path. Version control and build folders
    /// are skipped.
    private func findFiles(named text: String) throws -> [String] {
        let needle = text.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { throw ToolError("name is empty") }
        // The path-based walker gives paths relative to the root, whatever symlinks (such as /private) lead to it.
        guard let walker = FileManager.default.enumerator(atPath: try folder().path) else { return [] }
        var found: [String] = []
        var scanned = 0
        while let path = walker.nextObject() as? String {
            let name = (path as NSString).lastPathComponent
            if walker.fileAttributes?[.type] as? FileAttributeType == .typeDirectory {
                if Self.skippedFolders.contains(name) { walker.skipDescendants() }
                continue
            }
            scanned += 1
            if scanned > Self.maxScannedFiles || found.count >= Self.maxSearchHits { break }
            if name.range(of: needle, options: .caseInsensitive) != nil {
                found.append(path)
            }
        }
        return found.sorted()
    }

    private func searchText(_ query: String, in path: String? = nil, ignoreCase: Bool = false) throws -> String {
        guard !query.isEmpty else { throw ToolError("query is empty") }
        var hits: [String] = []
        let start: URL
        let prefix: String
        if let path, !path.isEmpty, path != "." {
            start = try resolve(path)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: start.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw ToolError("not a folder: \(path)")
            }
            prefix = String(start.path.dropFirst(try folder().path.count + 1))
        } else {
            start = try folder()
            prefix = ""
        }
        try searchFolder(start, relativeTo: prefix, query: query, ignoreCase: ignoreCase, hits: &hits)
        return hits.isEmpty ? "(no matches)" : hits.joined(separator: "\n")
    }

    private func searchFolder(_ folder: URL, relativeTo parent: String, query: String, ignoreCase: Bool,
                              hits: inout [String]) throws {
        let entries = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey])
        for url in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = url.lastPathComponent
            guard name != ".git", name != ".DS_Store", hits.count < Self.maxSearchHits else { continue }
            let path = parent.isEmpty ? name : parent + "/" + name
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                try searchFolder(url, relativeTo: path, query: query, ignoreCase: ignoreCase, hits: &hits)
            } else if let text = try? String(contentsOf: url, encoding: .utf8) {
                for (number, line) in text.components(separatedBy: "\n").enumerated()
                where ignoreCase ? line.range(of: query, options: .caseInsensitive) != nil : line.contains(query) {
                    hits.append("\(path):\(number + 1):\(line)")
                    if hits.count >= Self.maxSearchHits { break }
                }
            }
        }
    }

    /// Runs one read-only git command in the project folder. Only the fixed commands above reach here.
    private func git(_ arguments: [String]) throws -> String {
        #if os(macOS)
        try GitCommand.run(arguments, in: folder(), limit: Self.maxReadCharacters)
        #else
        throw ToolError("git tools are only available on the Mac host")
        #endif
    }

    /// The change a write or edit would make, for the diff in the chat. Nothing is written. Nil for other tools,
    /// and for an edit that would fail.
    func changePreview(name: String, arguments: String) -> FileChange? {
        guard let args = ToolArguments.parse(arguments), let path = args["path"] else { return nil }
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

    /// Runs one tool call off the main actor, so a long command or a slow page never freezes the window.
    /// The web check needs the main actor, so it hops back there on its own.
    @concurrent
    func execute(name: String, arguments: String) async -> String {
        if let connector = Connectors.connector(for: name) {
            guard connectors.contains(connector.id) else {
                return "error: the \(connector.name) connector is turned off. Mention !\(connector.id) in a message, or turn it on in Settings."
            }
            do {
                return try await Connectors.run(name, arguments: Connectors.stringArguments(arguments), root: root)
            } catch where NoInternet.matches(error, online: true) {
                return NoInternet.toolError(service: connector.name)
            } catch {
                return "error: \(error.localizedDescription)"
            }
        }
        #if os(macOS)
        if name == "web_check" {
            do {
                let args = ToolArguments.parse(arguments) ?? [:]
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
    /// A path the model wrote, such as "./App/a.swift", as the project-relative path it names ("App/a.swift").
    /// Nil when it leaves the project.
    func relativePath(_ path: String) -> String? {
        guard let root, let url = try? resolve(path) else { return nil }
        return url == root ? nil : String(url.path.dropFirst(root.path.count + 1))
    }

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
            throw ToolError("writing files is turned off. If the user wants Gatita to change files, they can turn on \"Let Gatita edit files in the project\" in Settings.")
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

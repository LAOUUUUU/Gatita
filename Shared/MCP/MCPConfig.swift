//
//  MCPConfig.swift
//  Gatita
//

import Foundation

/// One MCP server: a local one Gatita starts (a command, its arguments, and environment), or a remote one at a URL.
nonisolated struct MCPServerConfig: Codable, Equatable, Identifiable, Sendable {
    var name: String
    var command: String?
    var args: [String]
    var env: [String: String]
    var url: String?
    /// Kept in the file but not started.
    var disabled: Bool
    /// Its tools run without asking first.
    var trusted: Bool

    var id: String { name }
    var isRemote: Bool { url != nil }
}

/// One argument of an MCP tool, from its input schema.
nonisolated struct MCPToolParameter: Equatable, Sendable {
    let name: String
    let type: String
    let description: String?
    let required: Bool
}

/// mcp.json, in the shape Claude Desktop and other MCP apps use ({"mcpServers": {"name": {...}}}), plus how MCP
/// tools are named and described to the model. Tool names are "mcp__<server>__<tool>".
nonisolated enum MCPConfig {
    private struct File: Codable {
        var mcpServers: [String: Entry]?
    }

    private struct Entry: Codable {
        var command: String?
        var args: [String]?
        var env: [String: String]?
        var url: String?
        var disabled: Bool?
        var trusted: Bool?
    }

    static var defaultFile: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Gatita/mcp.json")
    }

    /// Claude Desktop's own file, which Settings can import from.
    static var claudeDesktopFile: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Claude/claude_desktop_config.json")
    }

    static func parse(_ data: Data) throws -> [MCPServerConfig] {
        let file = try JSONDecoder().decode(File.self, from: data)
        return (file.mcpServers ?? [:]).map { name, entry in
            MCPServerConfig(name: name, command: entry.command, args: entry.args ?? [], env: entry.env ?? [:],
                            url: entry.url, disabled: entry.disabled ?? false, trusted: entry.trusted ?? false)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func load(from file: URL) -> [MCPServerConfig] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        return (try? parse(data)) ?? []
    }

    static func save(_ servers: [MCPServerConfig], to file: URL) {
        var entries: [String: Entry] = [:]
        for server in servers {
            entries[server.name] = Entry(command: server.command, args: server.args.isEmpty ? nil : server.args,
                                         env: server.env.isEmpty ? nil : server.env, url: server.url,
                                         disabled: server.disabled ? true : nil, trusted: server.trusted ? true : nil)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(File(mcpServers: entries)) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    /// The servers found in another app's settings that Gatita does not have yet, by the names their tools use.
    static func importable(_ found: [MCPServerConfig], existing: [MCPServerConfig]) -> [MCPServerConfig] {
        let taken = Set(existing.map { serverKey($0.name) })
        return found.filter { !taken.contains(serverKey($0.name)) }
    }

    /// Why a name can't be used, or nil. Two servers whose names differ only in case or punctuation would give
    /// their tools the same names, so they count as the same.
    static func nameProblem(_ name: String, among servers: [MCPServerConfig], editing: String?) -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "Give the server a name." }
        if let other = servers.first(where: { $0.name != editing && serverKey($0.name) == serverKey(name) }) {
            return "There is already a server called \(other.name). Pick another name."
        }
        return nil
    }

    /// A server name as it appears in tool names: lower case, with anything but letters, digits, _ and - as _.
    static func serverKey(_ name: String) -> String {
        String(name.lowercased().map { $0.isLetter && $0.isASCII || $0.isNumber || $0 == "-" ? $0 : "_" })
    }

    static func toolName(server: String, tool: String) -> String {
        "mcp__\(serverKey(server))__\(tool)"
    }

    /// The server key and the tool's own name in an MCP tool name, or nil for any other tool.
    static func split(_ name: String) -> (server: String, tool: String)? {
        guard name.hasPrefix("mcp__") else { return nil }
        let rest = name.dropFirst(5)
        guard let separator = rest.range(of: "__") else { return nil }
        let server = String(rest[..<separator.lowerBound])
        let tool = String(rest[separator.upperBound...])
        return server.isEmpty || tool.isEmpty ? nil : (server, tool)
    }

    /// One line of the tool list the model reads: the call with each argument's type, then the first line of what
    /// the tool does.
    static func help(server: String, tool: String, description: String?, parameters: [MCPToolParameter]) -> String {
        let name = toolName(server: server, tool: tool)
        let arguments = parameters.map { parameter in
            let about = parameter.description?.components(separatedBy: "\n").first.map { ": \($0)" } ?? ""
            return #""\#(parameter.name)": "<\#(parameter.type)\#(parameter.required ? "" : ", optional")\#(about)>""#
        }
        let call = ([#""tool": "\#(name)""#] + arguments).joined(separator: ", ")
        let summary = description?.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespaces) ?? ""
        return "- \(name): {\(call)}" + (summary.isEmpty ? "" : " \(summary)")
    }

    // MARK: - Typing a server in Settings

    /// Arguments typed on one line, split at spaces, with "double quotes" around one that holds spaces.
    static func splitArguments(_ line: String) -> [String] {
        var arguments: [String] = []
        var current = ""
        var quoted = false
        var started = false
        for character in line {
            if character == "\"" {
                quoted.toggle()
                started = true
            } else if character == " ", !quoted {
                if started { arguments.append(current) }
                current = ""
                started = false
            } else {
                current.append(character)
                started = true
            }
        }
        if started { arguments.append(current) }
        return arguments
    }

    /// Arguments as one line, quoting any that hold a space.
    static func joinArguments(_ arguments: [String]) -> String {
        arguments.map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ")
    }

    /// KEY=VALUE lines as an environment. Blank lines and lines without "=" are left out.
    static func environment(from text: String) -> [String: String] {
        var environment: [String: String] = [:]
        for line in text.components(separatedBy: "\n") {
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            environment[key] = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        }
        return environment
    }

    static func environmentText(_ environment: [String: String]) -> String {
        environment.keys.sorted().map { "\($0)=\(environment[$0]!)" }.joined(separator: "\n")
    }

    /// The arguments of an MCP tool block, with their JSON types kept (numbers, true/false, lists, objects).
    static func arguments(in block: String) -> [String: Any]? {
        func object(_ text: String) -> [String: Any]? {
            try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        }
        guard var arguments = object(block) ?? object(ToolArguments.repaired(block)) else { return nil }
        arguments["tool"] = nil
        // The OpenAI shape: {"name": ..., "arguments": {...}}.
        if let nested = arguments["arguments"] as? [String: Any], arguments.count <= 2 {
            arguments = nested
        }
        return arguments
    }
}

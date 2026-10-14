//
//  MCPHub.swift
//  Gatita
//

import Foundation
import MCP
import Observation
#if os(macOS)
import System
#endif

/// Gatita's connections to MCP servers, with the official swift-sdk: each server's state, its tools for the model
/// (`toolHelp`), and calls to them. Local servers are started here (Mac only); remote ones are reached over HTTP.
@Observable
@MainActor
final class MCPHub {
    enum Status: Equatable {
        case off
        case connecting
        case connected(tools: Int)
        case failed(String)
    }

    /// Each server's state, by its key (`MCPConfig.serverKey`).
    private(set) var status: [String: Status] = [:]
    @ObservationIgnored private var connections: [String: Connection] = [:]

    /// The longest result sent back to the model.
    static let maxResult = 20_000
    /// How long a server has to answer when it starts, and a tool call to finish.
    @ObservationIgnored var startTimeout: Duration = .seconds(30)
    @ObservationIgnored var callTimeout: Duration = .seconds(300)
    /// Bumped by each connect and disconnect of a server, so a start that finishes after the server was removed
    /// or started again is thrown away instead of coming back.
    @ObservationIgnored private var generations: [String: Int] = [:]

    private struct Connection {
        var config: MCPServerConfig
        let client: Client
        let tools: [Tool]
        let process: AnyObject?
    }

    struct Problem: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// One line per tool of every connected server, for the model's tool list.
    var toolHelp: [String] {
        toolHelp(onlyTrusted: false)
    }

    /// The tool lines, of trusted servers only for places that can't ask first (the quick panel and Shortcuts).
    func toolHelp(onlyTrusted: Bool) -> [String] {
        connections.keys.sorted().filter { !onlyTrusted || connections[$0]!.config.trusted }.flatMap { key in
            connections[key]!.tools.map { tool in
                MCPConfig.help(server: key, tool: tool.name, description: tool.description,
                               parameters: Self.parameters(from: tool.inputSchema))
            }
        }
    }

    /// Whether a tool belongs to a server you trusted, so it runs without asking.
    func isTrusted(_ toolName: String) -> Bool {
        guard let server = MCPConfig.split(toolName)?.server else { return false }
        return connections[server]?.config.trusted == true
    }

    /// Takes a changed server's settings that need no restart, such as whether it is trusted.
    func update(_ server: MCPServerConfig) {
        connections[MCPConfig.serverKey(server.name)]?.config = server
    }

    /// Starts every server that is not turned off, side by side.
    func connectAll(_ servers: [MCPServerConfig]) async {
        await withTaskGroup(of: Void.self) { group in
            for server in servers where !server.disabled {
                group.addTask { await self.connect(server) }
            }
        }
    }

    /// Starts (or restarts) one server and reads its tools.
    func connect(_ server: MCPServerConfig) async {
        let key = MCPConfig.serverKey(server.name)
        await disconnect(server.name)
        let generation = (generations[key] ?? 0) + 1
        generations[key] = generation
        status[key] = .connecting
        var process: AnyObject?
        var processID: Int32?
        let client = Client(name: "Gatita", version: AppVersion.number)
        do {
            let transport: any Transport
            if let address = server.url {
                guard let url = URL(string: address), ["https", "http"].contains(url.scheme ?? "") else {
                    throw Problem(message: "\(address) is not an http or https address")
                }
                transport = HTTPClientTransport(endpoint: url, streaming: true)
            } else {
                #if os(macOS)
                let started = try await MCPProcess.start(server)
                process = started.process
                processID = started.process.processIdentifier
                transport = StdioTransport(input: started.input, output: started.output)
                #else
                throw Problem(message: "local MCP servers run on the Mac only. Add a remote one with its address")
                #endif
            }
            let pid = processID
            let tools = try await Self.withTimeout(startTimeout, what: "the server", onTimeout: {
                // Unblocks the waiting start: the client gives up its requests, and the server is stopped.
                await client.disconnect()
                if let pid { kill(pid, SIGTERM) }
            }) {
                _ = try await client.connect(transport: transport)
                var tools: [Tool] = []
                var cursor: String?
                repeat {
                    let page = try await client.listTools(cursor: cursor)
                    tools += page.tools
                    cursor = page.nextCursor
                } while cursor != nil && tools.count < 500
                return tools
            }
            guard generations[key] == generation else {
                await client.disconnect()
                Self.terminate(process)
                return
            }
            connections[key] = Connection(config: server, client: client, tools: tools, process: process)
            status[key] = .connected(tools: tools.count)
        } catch {
            Self.terminate(process)
            guard generations[key] == generation else { return }
            status[key] = .failed(error.localizedDescription)
        }
    }

    /// Stops one server, and any start of it still under way.
    func disconnect(_ name: String) async {
        let key = MCPConfig.serverKey(name)
        generations[key, default: 0] += 1
        guard let connection = connections.removeValue(forKey: key) else {
            if status[key] != nil { status[key] = .off }
            return
        }
        status[key] = .off
        await connection.client.disconnect()
        Self.terminate(connection.process)
    }

    /// Stops every local server at once, as Gatita quits.
    func stopAllNow() {
        for connection in connections.values { Self.terminate(connection.process) }
        connections = [:]
    }

    private static func terminate(_ process: AnyObject?) {
        #if os(macOS)
        (process as? Process)?.terminate()
        #endif
    }

    /// Calls an MCP tool with the block's arguments and returns its result as text, "error: …" when it failed.
    /// Stopping the reply ends a waiting call at once, and a call that takes longer than `callTimeout` is given up.
    func call(_ toolName: String, block: String) async -> String {
        guard let (server, tool) = MCPConfig.split(toolName), let connection = connections[server] else {
            return "error: no connected MCP server has the tool \(toolName). The user can check Settings, MCP Servers."
        }
        guard connection.tools.contains(where: { $0.name == tool }) else {
            return "error: the \(connection.config.name) server has no tool \(tool)."
        }
        guard let arguments = MCPConfig.arguments(in: block) else {
            return #"error: the tool block is not valid JSON, so nothing ran. Write one JSON object, such as {"tool": "\#(toolName)", ...}"#
        }
        let client = connection.client
        let values = arguments.isEmpty ? nil : arguments.mapValues(Self.value)
        do {
            let context: RequestContext<CallTool.Result> = try await client.callTool(name: tool, arguments: values)
            let id = context.requestID
            let result = try await withTaskCancellationHandler {
                try await Self.withTimeout(callTimeout, what: "the \(toolName) tool", onTimeout: {
                    try? await client.cancelRequest(id, reason: "Gatita stopped waiting")
                }) {
                    try await context.value
                }
            } onCancel: {
                Task { try? await client.cancelRequest(id, reason: "the user stopped the reply") }
            }
            let text = String(Self.text(of: result.content).prefix(Self.maxResult))
            return result.isError == true ? "error: \(text)" : text
        } catch is CancellationError {
            return "error: the call to \(toolName) was stopped."
        } catch {
            return "error: \(error.localizedDescription)"
        }
    }

    // MARK: - Converting

    /// A tool's arguments from its JSON schema: each property's name, type, description, and whether it is needed.
    static func parameters(from schema: Value) -> [MCPToolParameter] {
        guard case .object(let object) = schema, case .object(let properties)? = object["properties"] else { return [] }
        var required: Set<String> = []
        if case .array(let names)? = object["required"] {
            for case .string(let name) in names { required.insert(name) }
        }
        return properties.keys.sorted { (required.contains($0) ? 0 : 1, $0) < (required.contains($1) ? 0 : 1, $1) }.map { name in
            var type = "value"
            var description: String?
            if case .object(let property)? = properties[name] {
                if case .string(let text)? = property["type"] { type = text }
                if case .string(let text)? = property["description"] { description = text }
            }
            return MCPToolParameter(name: name, type: type, description: description, required: required.contains(name))
        }
    }

    /// A JSON value from JSONSerialization as an MCP value, keeping true and false apart from numbers.
    static func value(_ any: Any) -> Value {
        switch any {
        case let text as String:
            return .string(text)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
            let double = number.doubleValue
            return double == double.rounded() && abs(double) < 1e15 ? .int(number.intValue) : .double(double)
        case let list as [Any]:
            return .array(list.map(value))
        case let object as [String: Any]:
            return .object(object.mapValues(value))
        default:
            return .null
        }
    }

    /// A tool result as text: its text parts, and a note for each picture, sound, or link.
    static func text(of content: [Tool.Content]) -> String {
        content.map { item in
            switch item {
            case .text(let text, _, _): text
            case .image(_, let mimeType, _, _): "[a picture (\(mimeType)), not shown]"
            case .audio(_, let mimeType, _, _): "[a sound (\(mimeType)), not shown]"
            case .resource(let resource, _, _): resource.text ?? "[\(resource.uri)]"
            case .resourceLink(let uri, let name, _, _, _, _): "[\(name)](\(uri))"
            }
        }
        .joined(separator: "\n")
    }

    /// The work's result, or an error once `limit` passes. Then `onTimeout` runs first, which must make the work
    /// stop waiting (a task group waits for every child), so the timeout really ends the wait.
    private static func withTimeout<T: Sendable>(_ limit: Duration, what: String,
                                                 onTimeout: @escaping @Sendable () async -> Void,
                                                 _ work: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T?.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(for: limit)
                return nil
            }
            defer { group.cancelAll() }
            while let next = try await group.next() {
                if let value = next { return value }
                await onTimeout()
                let seconds = limit.components.seconds
                throw Problem(message: "\(what) did not answer within \(seconds) \(seconds == 1 ? "second" : "seconds")")
            }
            throw CancellationError()
        }
    }
}

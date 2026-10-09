//
//  GatitaClient.swift
//  Gatita
//
//  Created by LAOUUU on 2026-10-08.
//


import Foundation

/// Client for Gatita's OpenAI-compatible chat API (https://api.gatita.tech/v1).
/// Streams each reply. With `tools` set, the system message explains the
/// <gatita-tool> block format, and the client runs any block the model writes.
/// Every step is reported through `onEvent` so the UI can show it as it happens.
@MainActor
final class GatitaClient {
    nonisolated static let defaultBaseURL = URL(string: "https://api.gatita.tech/v1")!
    nonisolated static let maxToolRounds = 25
    nonisolated static let openTag = "<gatita-tool>"
    nonisolated static let closeTag = "</gatita-tool>"

    private let apiKey: String
    private let baseURL: URL
    private let model: String
    private let tools: ProjectTools?
    private let extraInstructions: String?
    private let tasks: TaskRegistry?
    private let session: URLSession

    init(apiKey: String,
         baseURL: URL = GatitaClient.defaultBaseURL,
         model: String = "gatita-7.1-max",
         tools: ProjectTools? = nil,
         extraInstructions: String? = nil,
         tasks: TaskRegistry? = nil) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
        self.tools = tools
        self.extraInstructions = extraInstructions
        self.tasks = tasks
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    /// The instructions a subagent runs with.
    nonisolated static let subagentInstructions = "You are a subagent working for Gatita on one task. Do only that task. Read the project as needed, and reply with the result in plain text. You cannot edit files, run commands, or start other subagents."

    /// Runs the tools that start, check, and stop background commands, and start and collect subagents. Nil for every other tool.
    private func runTaskTool(name: String, arguments: String, tools: ProjectTools) async -> String? {
        let taskToolNames: Set<String> = ["run_background", "task_status", "task_stop", "spawn_agent", "agent_result"]
        guard taskToolNames.contains(name) else { return nil }
        guard let registry = tasks else {
            return "error: background commands and subagents are not available here."
        }
        let args = (try? JSONDecoder().decode([String: String].self, from: Data(arguments.utf8))) ?? [:]

        switch name {
        case "run_background":
            guard tools.allowsBackground, let root = tools.root else {
                return "error: background commands need Code mode, a project folder, and running commands turned on in Settings."
            }
            guard let command = args["command"], let argv = CommandPolicy.allowed(command, tools.commands) else {
                return "error: that command is not on the allowed list, or it uses shell syntax"
            }
            do {
                let id = try registry.startBackground(argv, command: command, in: root)
                return "started background task \(id). It keeps running after this reply. Check it with task_status."
            } catch {
                return "error: \(error.localizedDescription)"
            }

        case "task_status":
            guard let id = args["id"] else { return "error: missing argument id" }
            guard let task = registry.backgroundTask(id) else { return "error: no background task with id \(id)" }
            let exit = task.exitCode.map { "exit code \($0)" } ?? "no exit code yet"
            return "status: \(String(describing: task.status))\n\(exit)\noutput:\n\(task.output.suffix(3000))"

        case "task_stop":
            guard let id = args["id"] else { return "error: missing argument id" }
            return registry.stopBackground(id) ? "stopped \(id)." : "error: \(id) is not running"

        case "spawn_agent":
            guard tools.allowsSubagents, let task = args["task"], !task.isEmpty else {
                return "error: spawn_agent needs Code mode, a project folder, and a task"
            }
            let agent = GatitaClient(apiKey: apiKey, baseURL: baseURL, model: model,
                                     tools: tools.readOnlyForSubagents(), extraInstructions: Self.subagentInstructions)
            let id = registry.spawnAgent(task: task, client: agent)
            return "started subagent \(id). It works alone in a read-only run. Get its answer with agent_result."

        case "agent_result":
            guard let id = args["id"] else { return "error: missing argument id" }
            return await registry.agentResult(id)

        default:
            return nil
        }
    }

    /// Plain request without events, used by the remote host path.
    func send(messages: [ChatMessage]) async throws -> String {
        try await stream(messages: messages) { _ in }
    }

    /// A chat message as the API takes it. Pictures go next to the text as data URLs.
    static func wire(_ message: ChatMessage) -> WireMessage {
        let images = message.attachedImages
        guard !images.isEmpty else {
            return WireMessage(role: message.role, content: message.sentText)
        }
        var parts = [WireContent.Part(type: "text", text: message.sentText, imageURL: nil)]
        for image in images {
            let url = "data:\(image.mimeType);base64,\(image.data.base64EncodedString())"
            parts.append(WireContent.Part(type: "image_url", text: nil, imageURL: .init(url: url)))
        }
        return WireMessage(role: message.role, content: .parts(parts))
    }

    /// Streams the reply and runs tool blocks as the model writes them.
    /// Returns the final text. `onEvent` is called on the main actor.
    @discardableResult
    func stream(messages: [ChatMessage], onEvent: (StreamEvent) -> Void) async throws -> String {
        var history = messages.map { GatitaClient.wire($0) }
        let system = [tools?.instructions, extraInstructions].compactMap { $0 }.filter { !$0.isEmpty }
        if !system.isEmpty {
            history.insert(WireMessage(role: "system", content: system.joined(separator: "\n\n")), at: 0)
        }

        var toolNumber = 0
        for _ in 0..<Self.maxToolRounds {
            let turn = try await streamTurn(history, onEvent: onEvent)
            guard let tools, let block = turn.toolBlock else {
                return turn.visible
            }

            // ask_user is not a tool: it hands the question to the user and ends the turn.
            if Self.toolName(in: block) == "ask_user" {
                onEvent(.question(Self.field("question", in: block) ?? ""))
                return turn.visible
            }

            // The model's words before the block, then the block itself, as it wrote them.
            history.append(WireMessage(role: "assistant",
                                       content: turn.visible + Self.openTag + block + Self.closeTag))
            toolNumber += 1
            let id = "t\(toolNumber)"
            let name = Self.toolName(in: block)
            onEvent(.toolStarted(id: id, name: name, arguments: block))
            let change = tools.changePreview(name: name, arguments: block)
            let result: String
            if let handled = await runTaskTool(name: name, arguments: block, tools: tools) {
                result = handled
            } else {
                result = await tools.execute(name: name, arguments: block)
            }
            onEvent(.toolFinished(id: id, name: name, result: result))
            if let change, !result.hasPrefix("error:") {
                onEvent(.fileChanged(id: id, change: change))
            }
            history.append(WireMessage(role: "user",
                                       content: "<gatita-tool-result name=\"\(name)\">\n\(result)\n</gatita-tool-result>"))
        }
        throw GatitaError.toolRoundLimit
    }

    private struct TurnResult {
        /// Text the user sees this turn. When a tool block was found, this is the text before it.
        let visible: String
        /// JSON inside the first complete <gatita-tool> block, if the model wrote one.
        let toolBlock: String?
    }

    /// One streamed model turn. The turn ends at the first complete tool block, so the model
    /// cannot invent a result for a tool it has not run yet.
    private func streamTurn(_ history: [WireMessage], onEvent: (StreamEvent) -> Void) async throws -> TurnResult {
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(ChatRequest(model: model, messages: history, stream: true))

        let (bytes, response) = try await session.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            var body = Data()
            for try await byte in bytes.prefix(300) { body.append(byte) }
            throw GatitaError.http(status: status, body: String(decoding: body, as: UTF8.self))
        }

        var pending = ""        // text received but not yet shown or parsed
        var visible = ""
        var toolBlock: String?
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                  let choice = chunk.choices.first else { continue }
            if choice.finishReason == "content_filter" {
                onEvent(.safetyStop)
            }
            let delta = choice.delta

            if let piece = delta.reasoningContent ?? delta.reasoning, !piece.isEmpty {
                onEvent(.reasoning(piece))
            }
            if let piece = delta.content, !piece.isEmpty {
                pending += piece
                let drained = Self.drain(&pending)
                if !drained.text.isEmpty {
                    visible += drained.text
                    onEvent(.text(drained.text))
                }
                if let block = drained.block {
                    toolBlock = block
                    break
                }
            }
        }

        if toolBlock == nil, !pending.isEmpty {
            visible += pending
            onEvent(.text(pending))
        }
        return TurnResult(visible: visible, toolBlock: toolBlock)
    }

    /// Splits `pending` into text that can be shown now and a finished tool block, if one is complete.
    /// An unfinished block, or a tail that might become the start of one, stays in `pending`.
    private static func drain(_ pending: inout String) -> (text: String, block: String?) {
        if let open = pending.range(of: openTag) {
            let text = String(pending[..<open.lowerBound])
            let afterOpen = pending[open.upperBound...]
            guard let close = afterOpen.range(of: closeTag) else {
                pending = String(pending[open.lowerBound...])
                return (text, nil)
            }
            let block = String(afterOpen[..<close.lowerBound])
            pending = ""
            return (text, block)
        }

        let holdBack = partialTagLength(pending)
        let cut = pending.index(pending.endIndex, offsetBy: -holdBack)
        let text = String(pending[..<cut])
        pending = String(pending[cut...])
        return (text, nil)
    }

    /// Length of the longest tail of `text` that is the start of the open tag.
    private static func partialTagLength(_ text: String) -> Int {
        for length in stride(from: min(openTag.count - 1, text.count), through: 1, by: -1)
        where openTag.hasPrefix(String(text.suffix(length))) {
            return length
        }
        return 0
    }

    /// One text field of a tool block, or nil.
    private static func field(_ name: String, in block: String) -> String? {
        let fields = try? JSONDecoder().decode([String: String].self, from: Data(block.utf8))
        return fields?[name]
    }

    /// The "tool" field of a block, or "unknown" when the block is not valid JSON.
    private static func toolName(in block: String) -> String {
        let fields = try? JSONDecoder().decode([String: String].self, from: Data(block.utf8))
        return fields?["tool"] ?? "unknown"
    }
}

/// One thing the UI can show while a reply streams.
nonisolated enum StreamEvent: Sendable {
    case text(String)
    case reasoning(String)
    case toolStarted(id: String, name: String, arguments: String)
    case toolFinished(id: String, name: String, result: String)
    /// Gatita asked the user something and is waiting for the answer.
    case question(String)
    /// The model stopped the reply because a safety filter fired (finish_reason "content_filter").
    case safetyStop
    /// A write or edit changed a file. The change is the diff the chat shows.
    case fileChanged(id: String, change: FileChange)
}

nonisolated enum GatitaError: LocalizedError {
    case http(status: Int, body: String)
    case toolRoundLimit

    /// The reason the server gave, from an error body such as {"error": {"message": "..."}}.
    /// Nil when the body has none, so the app never invents one.
    static func serverReason(in body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String, !message.isEmpty {
            return message
        }
        if let error = object["error"] as? String, !error.isEmpty {
            return error
        }
        if let message = object["message"] as? String, !message.isEmpty {
            return message
        }
        return nil
    }

    var errorDescription: String? {
        switch self {
        case .http(let status, let body):
            return "Gatita returned HTTP \(status): \(body)"
        case .toolRoundLimit:
            return "Gatita kept calling tools; stopped after \(GatitaClient.maxToolRounds) rounds."
        }
    }
}

/// A message's content as the API takes it: a plain string, or a list of parts when the message has pictures.
nonisolated enum WireContent: Codable, Sendable, Equatable {
    case text(String)
    case parts([Part])

    /// One piece of a multi-part message: text, or a picture as a data URL.
    struct Part: Codable, Sendable, Equatable {
        let type: String
        let text: String?
        let imageURL: ImageURL?

        struct ImageURL: Codable, Sendable, Equatable {
            let url: String
        }

        enum CodingKeys: String, CodingKey {
            case type, text
            case imageURL = "image_url"
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text):
            try container.encode(text)
        case .parts(let parts):
            try container.encode(parts)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
        } else {
            self = .parts(try container.decode([Part].self))
        }
    }
}

/// One message in OpenAI chat format.
nonisolated struct WireMessage: Codable, Sendable {
    let role: String
    let content: WireContent

    init(role: String, content: WireContent) {
        self.role = role
        self.content = content
    }

    init(role: String, content: String) {
        self.init(role: role, content: .text(content))
    }
}

private nonisolated struct ChatRequest: Encodable {
    let model: String
    let messages: [WireMessage]
    let stream: Bool
}

/// One `data:` payload of a streamed reply.
private nonisolated struct StreamChunk: Decodable {
    struct Choice: Decodable {
        let delta: Delta
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    struct Delta: Decodable {
        let content: String?
        let reasoning: String?
        let reasoningContent: String?

        enum CodingKeys: String, CodingKey {
            case content, reasoning
            case reasoningContent = "reasoning_content"
        }
    }

    let choices: [Choice]
}

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
    nonisolated static let maxToolRounds = 40
    /// How many times one reply may be asked to go on: after an empty turn, a cut-off, or an unfinished tool call.
    nonisolated static let maxNudges = 2
    nonisolated static let openTag = "<gatita-tool>"
    nonisolated static let closeTag = "</gatita-tool>"

    private let apiKey: String
    /// Whether to ask the server for usage in the stream. Turned off for good if the server refuses the option.
    private var sendsUsageOption = true
    private let baseURL: URL
    private let model: String
    private let tools: ProjectTools?
    private let extraInstructions: String?
    private let tasks: TaskRegistry?
    /// Runs an MCP tool ("mcp__<server>__<tool>") with its block, through `MCPHub`. Nil offers none.
    private let mcp: (@MainActor @Sendable (String, String) async -> String)?
    /// Records what write_file and edit_file change, so the reply can be undone. Nil records nothing.
    private let checkpoints: CheckpointRecorder?
    /// Asked before run_command and run_background run. Nil runs them without asking.
    private let approveCommand: (@MainActor @Sendable (CommandApproval.Request) async -> CommandApproval.Decision)?
    private let session: URLSession

    init(apiKey: String,
         baseURL: URL = GatitaClient.defaultBaseURL,
         model: String = "gatita-7.1-max",
         tools: ProjectTools? = nil,
         extraInstructions: String? = nil,
         tasks: TaskRegistry? = nil,
         approveCommand: (@MainActor @Sendable (CommandApproval.Request) async -> CommandApproval.Decision)? = nil,
         checkpoints: CheckpointRecorder? = nil,
         mcp: (@MainActor @Sendable (String, String) async -> String)? = nil) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
        self.tools = tools
        self.extraInstructions = extraInstructions
        self.tasks = tasks
        self.approveCommand = approveCommand
        self.checkpoints = checkpoints
        self.mcp = mcp
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
        let args = ToolArguments.parse(arguments) ?? [:]

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
            guard registry.backgroundTask(id) != nil else { return "error: no background task with id \(id)" }
            // Wait for a running task before answering, so the model doesn't poll a status that has not changed.
            let deadline = Date().addingTimeInterval(TaskStatusText.waitSeconds(args["wait"]))
            while registry.backgroundTask(id)?.status == .running, Date() < deadline, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            guard let task = registry.backgroundTask(id) else { return "error: no background task with id \(id)" }
            let exit = task.exitCode.map { "exit code \($0)" } ?? "no exit code yet"
            let running = task.status == .running
            return "status: \(String(describing: task.status))\n\(exit)\n\(TaskStatusText.note(running: running))\noutput:\n\(task.output.suffix(3000))"

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
        var nudges = 0
        var carried = "" // text shown since the last tool call, from turns that were asked to go on
        var lastBlock: String? // the previous tool call, to notice the same call twice in a row
        for _ in 0..<Self.maxToolRounds {
            let turn = try await turn(history, onEvent: onEvent)

            if let tools, let block = turn.toolBlock {
                // ask_user is not a tool: it hands the question to the user and ends the turn.
                if Self.toolName(in: block) == "ask_user", tools.allowsReports {
                    onEvent(.question(Self.field("question", in: block) ?? ""))
                    return carried + turn.visible
                }

                // The model's words before the block, then the block itself, as it wrote them.
                history.append(WireMessage(role: "assistant",
                                           content: turn.visible + Self.openTag + block + Self.closeTag))
                let name = Self.toolName(in: block)
                let result: String
                if name == "batch" {
                    result = await runBatch(block, tools: tools, toolNumber: &toolNumber, onEvent: onEvent)
                } else {
                    toolNumber += 1
                    result = await runCall(name: name, block: block, tools: tools, id: "t\(toolNumber)", onEvent: onEvent)
                }
                // The note is for the model only, so the chat still sees an error as an error.
                let repeated = ToolRepeat.isRepeat(block, of: lastBlock)
                lastBlock = block
                let shown = repeated ? ToolRepeat.note + "\n" + result : result
                history.append(WireMessage(role: "user",
                                           content: "<gatita-tool-result name=\"\(name)\">\n\(shown)\n</gatita-tool-result>"))
                carried = ""
                continue
            }

            // No tool call. A finished reply is returned. One that stopped for no good reason is asked to go on.
            guard let ending = TurnEnding.classify(visible: turn.visible, finishReason: turn.finishReason,
                                                   endedCleanly: turn.endedCleanly, unfinishedBlock: turn.unfinishedBlock,
                                                   hasTools: tools != nil) else {
                return carried + turn.visible
            }
            guard nudges < Self.maxNudges, let note = ending.nudge(hasTools: tools != nil) else {
                if ending.isErrorWhenExhausted { throw GatitaError.endedEarly(ending) }
                return carried + turn.visible
            }
            nudges += 1
            if ending == .unfinished {
                onEvent(.text("\n\n"))
                carried += turn.visible + "\n\n"
            } else {
                carried += turn.visible
            }
            Self.goOn(after: turn.visible, note: note, history: &history)
        }
        throw GatitaError.toolRoundLimit
    }

    /// Runs one tool call and reports it to the chat: started, finished, and the file change it made, if any.
    private func runCall(name: String, block: String, tools: ProjectTools, id: String,
                         onEvent: (StreamEvent) -> Void) async -> String {
        onEvent(.toolStarted(id: id, name: name, arguments: block))
        let change = tools.changePreview(name: name, arguments: block)
        // The file as it was, before the reply's first change to it.
        let changed = name == "write_file" || name == "edit_file"
            ? ToolArguments.parse(block)?["path"].flatMap(tools.relativePath) : nil
        if let changed { checkpoints?.before(changed) }
        let result: String
        if let denial = await askBeforeCommand(name: name, block: block, tools: tools) {
            result = denial
        } else if name.hasPrefix("mcp__"), let mcp {
            result = await mcp(name, block)
        } else if let handled = await runTaskTool(name: name, arguments: block, tools: tools) {
            result = handled
        } else {
            result = await tools.execute(name: name, arguments: block)
        }
        if let changed, !result.hasPrefix("error:") { checkpoints?.after(changed) }
        onEvent(.toolFinished(id: id, name: name, result: result))
        if let change, !result.hasPrefix("error:") {
            onEvent(.fileChanged(id: id, change: change))
        }
        return result
    }

    /// Waits for the user's answer before a command runs. The denial to send back, or nil to go ahead. A command
    /// that is not allowed at all, or with commands off, is left for the tool to refuse.
    private func askBeforeCommand(name: String, block: String, tools: ProjectTools) async -> String? {
        // An MCP tool is asked about by its name, with its arguments shown. "Always" allows that one tool.
        if name.hasPrefix("mcp__") {
            guard mcp != nil, let approveCommand else { return nil }
            let arguments = MCPConfig.arguments(in: block)
                .flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) }
                .flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let shown = String((name + " " + arguments).prefix(400))
            let decision = await approveCommand(CommandApproval.Request(command: shown, rule: name))
            return decision == .deny ? CommandApproval.denial(name) : nil
        }
        guard name == "run_command" || name == "run_background", let approveCommand, tools.allowCommands,
              let command = ToolArguments.parse(block)?["command"],
              let rule = CommandApproval.rule(for: command, allowed: tools.commands) else { return nil }
        let decision = await approveCommand(CommandApproval.Request(command: command, rule: rule))
        return decision == .deny ? CommandApproval.denial(command) : nil
    }

    /// Runs each call of a batch in order, each shown in the chat as its own tool call, and joins their results.
    /// A batch that can't be read shows as one failed "batch" call.
    private func runBatch(_ block: String, tools: ProjectTools, toolNumber: inout Int,
                          onEvent: (StreamEvent) -> Void) async -> String {
        let calls: [String]
        do {
            calls = try ToolBatch.calls(in: block)
        } catch {
            toolNumber += 1
            let result = "error: \(error.localizedDescription)"
            onEvent(.toolStarted(id: "t\(toolNumber)", name: "batch", arguments: block))
            onEvent(.toolFinished(id: "t\(toolNumber)", name: "batch", result: result))
            return result
        }
        var results: [(name: String, result: String)] = []
        for call in calls {
            guard !Task.isCancelled else { break }
            toolNumber += 1
            let name = Self.toolName(in: call)
            results.append((name, await runCall(name: name, block: call, tools: tools, id: "t\(toolNumber)", onEvent: onEvent)))
        }
        return ToolBatch.combine(results)
    }

    /// Adds what the model said so far and the note asking it to go on. An empty message is not sent back, so the
    /// note joins the last user message instead, which keeps the roles alternating.
    private static func goOn(after said: String, note: String, history: inout [WireMessage]) {
        if said.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let last = history.last, last.role == "user", case .text(let text) = last.content {
                history[history.count - 1] = WireMessage(role: "user", content: text + "\n\n" + note)
            } else {
                history.append(WireMessage(role: "user", content: note))
            }
        } else {
            history.append(WireMessage(role: "assistant", content: said))
            history.append(WireMessage(role: "user", content: note))
        }
    }

    private struct TurnResult {
        /// Text the user sees this turn. When a tool block was found, this is the text before it.
        let visible: String
        /// JSON inside the first complete <gatita-tool> block, if the model wrote one.
        let toolBlock: String?
        /// Why the server said it stopped (finish_reason), if it said.
        let finishReason: String?
        /// True when the stream ended with [DONE] or a finish reason. False when the connection just closed.
        let endedCleanly: Bool
        /// What followed an opening tool tag that never closed, when that is not a whole tool call.
        let unfinishedBlock: String?
    }

    /// Whether a server refused the usage option, so the request must go without it.
    /// A 400 or 422 that names the option, in any case, as "stream_options" or "include_usage".
    nonisolated static func rejectsStreamOptions(status: Int, body: String) -> Bool {
        let text = body.lowercased()
        return [400, 422].contains(status) && (text.contains("stream_options") || text.contains("include_usage"))
    }

    /// One turn. A rate limit (HTTP 429) is waited out and the turn sent again, up to `RateLimit.maxWaits` times;
    /// after that, or when the wait would be too long, the 429 is the error.
    private func turn(_ history: [WireMessage], onEvent: (StreamEvent) -> Void) async throws -> TurnResult {
        var waits = 0
        while true {
            do {
                return try await usageTurn(history, onEvent: onEvent)
            } catch GatitaError.rateLimited(let delay, let body) {
                guard waits < RateLimit.maxWaits, let seconds = RateLimit.waitSeconds(delay) else {
                    throw GatitaError.http(status: 429, body: body)
                }
                waits += 1
                onEvent(.waiting(seconds: Int(seconds.rounded(.up))))
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
        }
    }

    /// One turn with the usage option. If the server refuses the option, the client drops it and sends again.
    private func usageTurn(_ history: [WireMessage], onEvent: (StreamEvent) -> Void) async throws -> TurnResult {
        guard sendsUsageOption else {
            return try await streamTurn(history, onEvent: onEvent, includeUsage: false)
        }
        do {
            return try await streamTurn(history, onEvent: onEvent, includeUsage: true)
        } catch GatitaError.http(let status, let body) where Self.rejectsStreamOptions(status: status, body: body) {
            sendsUsageOption = false
            return try await streamTurn(history, onEvent: onEvent, includeUsage: false)
        }
    }

    /// One streamed model turn. The turn ends at the first complete tool block, so the model
    /// cannot invent a result for a tool it has not run yet.
    private func streamTurn(_ history: [WireMessage], onEvent: (StreamEvent) -> Void, includeUsage: Bool) async throws -> TurnResult {
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        var body = ChatRequest(model: model, messages: history, stream: true)
        if includeUsage {
            body.streamOptions = ChatRequest.StreamOptions(includeUsage: true)
        }
        request.httpBody = try JSONEncoder().encode(body)

        let (bytes, response) = try await session.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            var body = Data()
            for try await byte in bytes.prefix(300) { body.append(byte) }
            let text = String(decoding: body, as: UTF8.self)
            if status == 429 {
                let header = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After")
                throw GatitaError.rateLimited(retryAfter: RateLimit.delay(header: header, body: text), body: text)
            }
            throw GatitaError.http(status: status, body: text)
        }

        var pending = ""        // text received but not yet shown or parsed
        var visible = ""
        var toolBlock: String?
        var finishReason: String?
        var sawDone = false
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" {
                sawDone = true
                break
            }
            // The usage arrives in a chunk with no choices, so it is read before the choices are checked.
            if let usage = TokenUsage.read(fromChunk: payload) {
                onEvent(.usage(usage))
            }
            guard let data = payload.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                  let choice = chunk.choices.first else { continue }
            if let reason = choice.finishReason {
                finishReason = reason
            }
            if choice.finishReason == "content_filter" {
                onEvent(.safetyStop)
            }
            let delta = choice.delta

            if let piece = delta.reasoningContent ?? delta.reasoning, !piece.isEmpty {
                onEvent(.reasoning(piece))
            }
            if let piece = delta.content, !piece.isEmpty {
                pending += piece
                if ReplyCheck.stopsStream(at: String(visible.suffix(200)) + pending) {
                    throw GatitaError.garbled(sample: String((visible + pending).suffix(400)))
                }
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

        var unfinishedBlock: String?
        if toolBlock == nil, pending.hasPrefix(Self.openTag) {
            // The stream ended inside a tool block. If its JSON is whole, the model only forgot the closing tag.
            let rest = String(pending.dropFirst(Self.openTag.count))
            if let object = TurnEnding.completeObject(in: rest), ToolArguments.parse(object) != nil {
                toolBlock = object
            } else {
                unfinishedBlock = rest
            }
        } else if toolBlock == nil, !pending.isEmpty {
            visible += pending
            onEvent(.text(pending))
        }
        return TurnResult(visible: visible, toolBlock: toolBlock, finishReason: finishReason,
                          endedCleanly: sawDone || finishReason != nil, unfinishedBlock: unfinishedBlock)
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
        ToolArguments.parse(block)?[name]
    }

    /// The "tool" field of a block, or "unknown" when the block is not valid JSON.
    private static func toolName(in block: String) -> String {
        ToolArguments.parse(block)?["tool"] ?? "unknown"
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
    /// Tokens used by one round of the reply, when the server sends them in the stream.
    case usage(TokenUsage)
    /// A write or edit changed a file. The change is the diff the chat shows.
    case fileChanged(id: String, change: FileChange)
    /// The API's rate limit was reached. The client waits this many seconds, then sends the turn again.
    case waiting(seconds: Int)
}

nonisolated enum GatitaError: LocalizedError {
    case http(status: Int, body: String)
    case toolRoundLimit
    /// The reply leaked a control token, so the stream was stopped. `sample` is the end of the text received.
    case garbled(sample: String)
    /// The reply ended for no good reason and asking the model to go on did not help.
    case endedEarly(TurnEnding)
    /// HTTP 429. Waited out inside the client; it reaches the app as `.http(429, ...)` once the waits are used up.
    case rateLimited(retryAfter: TimeInterval?, body: String)

    /// The reason the server gave, from an error body such as {"error": {"message": "..."}}.
    /// Nil when the body has none, so the app never invents one.
    static func serverReason(in body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String, !message.isEmpty {
            return message
        }
        if let error = object["error"] as? String, !error.isEmpty {
            if let message = object["message"] as? String, !message.isEmpty, message != error {
                return "\(error) (\(message))"
            }
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
            return "Gatita made \(GatitaClient.maxToolRounds) rounds of tool calls on this reply, so it was paused."
        case .garbled:
            return "Gatita's reply came back garbled, so it was stopped."
        case .endedEarly(let ending):
            return ending.explanation
        case .rateLimited(_, let body):
            return "Gatita returned HTTP 429: \(body)"
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
    var streamOptions: StreamOptions? = nil

    enum CodingKeys: String, CodingKey {
        case model, messages, stream
        case streamOptions = "stream_options"
    }

    struct StreamOptions: Encodable {
        let includeUsage: Bool

        enum CodingKeys: String, CodingKey {
            case includeUsage = "include_usage"
        }
    }
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

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
    private let session: URLSession

    init(apiKey: String,
         baseURL: URL = GatitaClient.defaultBaseURL,
         model: String = "gatita-7.1-max",
         tools: ProjectTools? = nil,
         extraInstructions: String? = nil) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
        self.tools = tools
        self.extraInstructions = extraInstructions
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    /// Plain request without events, used by the remote host path.
    func send(messages: [ChatMessage]) async throws -> String {
        try await stream(messages: messages) { _ in }
    }

    /// Streams the reply and runs tool blocks as the model writes them.
    /// Returns the final text. `onEvent` is called on the main actor.
    @discardableResult
    func stream(messages: [ChatMessage], onEvent: (StreamEvent) -> Void) async throws -> String {
        var history = messages.map { WireMessage(role: $0.role, content: $0.sentText) }
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
            let result = await tools.execute(name: name, arguments: block)
            onEvent(.toolFinished(id: id, name: name, result: result))
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
                  let delta = chunk.choices.first?.delta else { continue }

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
}

nonisolated enum GatitaError: LocalizedError {
    case http(status: Int, body: String)
    case toolRoundLimit

    var errorDescription: String? {
        switch self {
        case .http(let status, let body):
            return "Gatita returned HTTP \(status): \(body)"
        case .toolRoundLimit:
            return "Gatita kept calling tools; stopped after \(GatitaClient.maxToolRounds) rounds."
        }
    }
}

/// One message in OpenAI chat format.
nonisolated struct WireMessage: Codable, Sendable {
    let role: String
    let content: String
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

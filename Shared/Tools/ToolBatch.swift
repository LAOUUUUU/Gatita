//
//  ToolBatch.swift
//  Gatita
//

import Foundation

/// The batch tool: up to 10 tool calls in one step, so a model that needs several things that don't depend on each
/// other asks for them in one request instead of one round trip each. The client runs them in order, each as its
/// own tool call in the chat, and sends back one result with each call's answer between start and end lines.
nonisolated enum ToolBatch {
    static let maxCalls = 10

    /// Each call of a batch block as its own JSON object, ready to run like a block of its own.
    static func calls(in block: String) throws -> [String] {
        let object = (try? JSONSerialization.jsonObject(with: Data(block.utf8)) as? [String: Any])
            ?? (try? JSONSerialization.jsonObject(with: Data(ToolArguments.repaired(block).utf8)) as? [String: Any])
        guard let list = object?["calls"] as? [Any] else {
            throw ToolError(#"batch needs "calls": a list of tool calls, such as [{"tool": "read_file", "path": "a.swift"}, {"tool": "search_text", "query": "x"}]"#)
        }
        guard !list.isEmpty else { throw ToolError("batch has no calls in it") }
        guard list.count <= maxCalls else {
            throw ToolError("\(list.count) calls is too many for one batch. Send at most \(maxCalls).")
        }
        return try list.enumerated().map { index, item in
            guard let call = item as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: call, options: [.sortedKeys]),
                  let text = String(data: data, encoding: .utf8),
                  let name = ToolArguments.parse(text)?["tool"] else {
                throw ToolError("call \(index + 1) of the batch is not a tool call with a \"tool\" field")
            }
            guard name != "batch", name != "ask_user" else {
                throw ToolError("call \(index + 1) is \(name), which cannot run inside a batch")
            }
            return text
        }
    }

    /// The one result the model gets back: each call's answer between a start line and an end line.
    static func combine(_ results: [(name: String, result: String)]) -> String {
        let parts = results.enumerated().map { index, item in
            "===== result \(index + 1): \(item.name) =====\n\(item.result)\n===== end of result \(index + 1) ====="
        }
        return (["Ran \(results.count) calls."] + parts).joined(separator: "\n\n")
    }
}

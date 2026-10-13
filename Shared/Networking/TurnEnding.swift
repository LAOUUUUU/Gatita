//
//  TurnEnding.swift
//  Gatita
//

import Foundation

/// How a model turn that made no tool call ended, when it ended for no good reason.
/// A finished reply has no ending. The others are answered by asking the model to go on, a few times.
nonisolated enum TurnEnding: Equatable, Sendable {
    /// Nothing was written.
    case empty
    /// The server stopped at its length limit.
    case cutOff
    /// A tool block was started and never finished.
    case toolCallCutOff
    /// The text ends in a colon with no tool call after it: an action was announced and never made.
    case unfinished
    /// The connection closed with no finish reason and no end marker.
    case closedEarly

    /// What was wrong with a turn that has no tool call, or nil when the reply is finished.
    static func classify(visible: String, finishReason: String?, endedCleanly: Bool,
                         unfinishedBlock: String?, hasTools: Bool) -> TurnEnding? {
        // A safety stop is reported on its own, and asking the model again would not help.
        if finishReason == "content_filter" { return nil }
        if unfinishedBlock != nil { return .toolCallCutOff }
        if finishReason == "length" { return .cutOff }
        let text = visible.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return .empty }
        if !endedCleanly { return .closedEarly }
        if hasTools, text.hasSuffix(":") { return .unfinished }
        return nil
    }

    /// What the client tells the model to get it going again. Nil when asking again would not help.
    func nudge(hasTools: Bool) -> String? {
        switch self {
        case .empty:
            return hasTools
                ? "Your last message was empty. Answer the user now. If you need a tool, write the tool block."
                : "Your last message was empty. Answer the user now."
        case .cutOff:
            return "Your last message was cut off. Continue exactly where you stopped, and do not repeat anything."
        case .toolCallCutOff:
            return "Your tool call was cut off before it finished. Write the whole tool block again."
        case .unfinished:
            return "Your last message ended with a colon but made no tool call. If you meant to call a tool, write the tool block now. If you were done, say so in one short sentence."
        case .closedEarly:
            return nil
        }
    }

    /// Whether the reply is an error once the nudges are used up. A reply that only ends in a colon still has its text.
    var isErrorWhenExhausted: Bool {
        self != .unfinished
    }

    /// What the chat says when the reply ended this way.
    var explanation: String {
        switch self {
        case .empty: "Gatita ended the reply without writing an answer."
        case .cutOff: "Gatita's reply hit its length limit and was cut off."
        case .toolCallCutOff: "Gatita's tool call was cut off before it finished."
        case .unfinished: "Gatita's reply stopped after announcing an action it never took."
        case .closedEarly: "The connection closed before Gatita finished its reply."
        }
    }

    /// The first complete JSON object at the start of the text, or nil when it is cut off or the text does not start
    /// with one. Braces inside strings do not count. Used when a tool block was never closed.
    static func completeObject(in text: String) -> String? {
        let characters = Array(text.drop { $0.isWhitespace })
        guard characters.first == "{" else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        for (index, character) in characters.enumerated() {
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }
            switch character {
            case "\"":
                inString = true
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return String(characters[...index]) }
            default:
                break
            }
        }
        return nil
    }
}

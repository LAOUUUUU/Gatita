//
//  TranscriptView.swift
//  Gatita
//

import Foundation

/// How much of a reply the chat shows. Normal is only the text Gatita writes. Thinking adds its thinking and
/// tool calls, folded. Verbose shows everything open.
nonisolated enum TranscriptView: String, Codable, CaseIterable, Identifiable, Sendable {
    case normal
    case thinking
    case verbose

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal: "Normal"
        case .thinking: "Thinking"
        case .verbose: "Verbose"
        }
    }

    /// What the view shows, for the menu that picks it.
    var summary: String {
        switch self {
        case .normal: "Only the text Gatita writes"
        case .thinking: "Adds its thinking and tool calls, folded"
        case .verbose: "Everything, opened up"
        }
    }

    var showsThinking: Bool { self != .normal }
    var showsToolCalls: Bool { self != .normal }
    var expandsThinking: Bool { self == .verbose }
    var expandsToolCalls: Bool { self == .verbose }
}

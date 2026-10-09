//
//  ReplyCheck.swift
//  Gatita
//

import Foundation

/// Catches replies where the model leaked its chat-template control tokens, such as <|close|>.
nonisolated enum ReplyCheck {
    /// A control token: "<|", a name, then "|>". Ordinary code with a pipe, such as "|>", does not match.
    private static let controlToken = #"<\|[A-Za-z_]+\|>"#

    static func isCorrupted(_ text: String) -> Bool {
        text.range(of: controlToken, options: .regularExpression) != nil
    }

    static func stripControlTokens(_ text: String) -> String {
        text.replacingOccurrences(of: controlToken, with: "", options: .regularExpression)
    }
}

//
//  TokenEstimate.swift
//  Gatita
//

import Foundation

/// A rough token count for a reply the server did not count: about four characters to a token.
/// Digits and code often take more tokens than that, so an estimate can be low.
nonisolated enum TokenEstimate {
    static func tokens(_ text: String) -> Int {
        (text.count + 3) / 4
    }

    /// The estimate for one reply: the messages sent to Gatita, and the reply it wrote back.
    static func usage(sentText: [String], reply: String) -> TokenUsage {
        TokenUsage(promptTokens: sentText.reduce(0) { $0 + tokens($1) },
                   completionTokens: tokens(reply),
                   isEstimate: true)
    }
}

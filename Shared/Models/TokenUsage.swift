//
//  TokenUsage.swift
//  Gatita
//

import Foundation

/// Tokens a reply used: what was sent in, and what came back out.
nonisolated struct TokenUsage: Codable, Hashable, Sendable {
    let promptTokens: Int
    let completionTokens: Int
    /// True when Gatita did not count the tokens, so they are estimated from the text.
    let isEstimate: Bool

    init(promptTokens: Int, completionTokens: Int, isEstimate: Bool = false) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.isEstimate = isEstimate
    }

    /// Reads a saved count. Counts saved before the estimate flag existed are server counts.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        promptTokens = try values.decode(Int.self, forKey: .promptTokens)
        completionTokens = try values.decode(Int.self, forKey: .completionTokens)
        isEstimate = try values.decodeIfPresent(Bool.self, forKey: .isEstimate) ?? false
    }

    /// For example "1,234 in · 567 out", with thousands grouped. Estimates say so.
    var summary: String {
        let text = "\(Self.grouped(promptTokens)) in · \(Self.grouped(completionTokens)) out"
        return isEstimate ? text + " (estimated)" : text
    }

    /// The usage of several tool rounds added together.
    func adding(_ other: TokenUsage) -> TokenUsage {
        TokenUsage(promptTokens: promptTokens + other.promptTokens,
                   completionTokens: completionTokens + other.completionTokens,
                   isEstimate: isEstimate || other.isEstimate)
    }

    /// The usage object in one streamed `data:` payload, or nil when the payload has none.
    static func read(fromChunk json: String) -> TokenUsage? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let usage = object["usage"] as? [String: Any],
              let prompt = usage["prompt_tokens"] as? Int,
              let completion = usage["completion_tokens"] as? Int else { return nil }
        return TokenUsage(promptTokens: prompt, completionTokens: completion)
    }

    /// 1234 becomes "1,234".
    static func grouped(_ number: Int) -> String {
        var result = ""
        for (index, digit) in String(number).reversed().enumerated() {
            if index > 0 && index % 3 == 0 { result.append(",") }
            result.append(digit)
        }
        return String(result.reversed())
    }
}

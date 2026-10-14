//
//  SpeechText.swift
//  Gatita
//

import Foundation

/// A reply as words to read aloud: Markdown marks, links, and code are left out, since they read badly.
nonisolated enum SpeechText {
    static func plain(from markdown: String) -> String {
        var lines: [String] = []
        var inCode = false
        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if !inCode { lines.append(trimmed.hasPrefix("```chart") ? "Chart skipped." : "Code block skipped.") }
                inCode.toggle()
                continue
            }
            if inCode { continue }
            var text = trimmed
            // Separator rows of tables, and rules.
            if !text.isEmpty, text.allSatisfy({ "-|: *_".contains($0) }) { continue }
            while text.hasPrefix("#") || text.hasPrefix(">") { text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces) }
            for marker in ["- ", "* ", "+ "] where text.hasPrefix(marker) { text = String(text.dropFirst(2)) }
            text = replace(text, #"!?\[([^\]]*)\]\([^)]*\)"#, "$1")   // links and images keep their words
            text = replace(text, #"(\*\*|__|\*|`)"#, "")
            text = text.replacingOccurrences(of: "|", with: ", ")
            lines.append(text)
        }
        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private static func replace(_ text: String, _ pattern: String, _ template: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
        return expression.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }
}

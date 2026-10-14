//
//  MathDetection.swift
//  Gatita
//

import Foundation

/// Whether a paragraph holds math to draw with LaTeX. Models write $…$, \(…\), $$…$$, and \[…\]; a dollar sign
/// is also money and shell variables, so a single-dollar span counts only when it looks like math: no space just
/// inside the dollars, and a letter alone or TeX marks such as \, ^, _, =, or braces. Code spans never count.
nonisolated enum MathDetection {
    private static let codeSpan = try! NSRegularExpression(pattern: "`[^`]*`")
    private static let singleDollar = try! NSRegularExpression(pattern: #"(?<![\\$\w])\$(?!\s)([^$\n]+?)(?<!\s)\$(?![\w$])"#)

    static func containsMath(_ text: String) -> Bool {
        let text = codeSpan.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        if hasPair(text, open: "\\(", close: "\\)") || hasPair(text, open: "\\[", close: "\\]") { return true }
        if let open = text.range(of: "$$"), text[open.upperBound...].contains("$$") { return true }
        for match in singleDollar.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range(at: 1), in: text) else { continue }
            if looksLikeMath(String(text[range])) { return true }
        }
        return false
    }

    private static let kept = [#"\$\$[\s\S]+?\$\$"#, #"\\\([\s\S]+?\\\)"#, #"\\\[[\s\S]+?\\\]"#, "`[^`]*`"]
        .map { try! NSRegularExpression(pattern: $0) }

    /// The text with every dollar sign that is not part of math escaped (\$), so the LaTeX view shows prices as
    /// text even in a paragraph that also holds math. Math spans, code spans, and escaped dollars are left alone.
    static func escapingStrayDollars(_ text: String) -> String {
        let string = text as NSString
        let whole = NSRange(location: 0, length: string.length)
        var keep = kept.flatMap { $0.matches(in: text, range: whole).map(\.range) }
        for match in singleDollar.matches(in: text, range: whole)
        where looksLikeMath(string.substring(with: match.range(at: 1)))
            && !keep.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
            keep.append(match.range)
        }
        let result = NSMutableString(string: text)
        for index in stride(from: string.length - 1, through: 0, by: -1) where string.character(at: index) == 0x24 {
            let escaped = index > 0 && string.character(at: index - 1) == 0x5C
            if !escaped, !keep.contains(where: { NSLocationInRange(index, $0) }) {
                result.insert("\\", at: index)
            }
        }
        return result as String
    }

    private static func hasPair(_ text: String, open: String, close: String) -> Bool {
        guard let start = text.range(of: open) else { return false }
        return text[start.upperBound...].contains(close)
    }

    private static func looksLikeMath(_ inner: String) -> Bool {
        if inner.count == 1, inner.first?.isLetter == true { return true }
        return inner.contains { "\\^_={}".contains($0) }
    }
}

/// Code fences drawn as something richer than code: Mermaid diagrams, and display math.
nonisolated enum RichCode {
    enum Kind: Equatable {
        case code, diagram, math
    }

    static func kind(language: String) -> Kind {
        switch language.lowercased() {
        case "mermaid": .diagram
        case "math", "latex", "tex", "katex": .math
        default: .code
        }
    }

    /// A math fence's text as one display equation for the LaTeX view.
    static func displayMath(_ code: String) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 4, trimmed.hasPrefix("$$"), trimmed.hasSuffix("$$") { return trimmed }
        return "$$\(trimmed)$$"
    }
}

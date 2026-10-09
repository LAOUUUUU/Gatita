//
//  MarkdownBlocks.swift
//  Gatita
//

import Foundation

/// The block-level parts of a chat reply. Inline styling (bold, code, links) stays inside each block's text.
nonisolated enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case bullet(text: String)
    case numbered(number: Int, text: String)
    case code(language: String, text: String)
}

/// Splits a reply into blocks. It handles the common cases a chat reply uses; it is not a full CommonMark parser.
nonisolated enum MarkdownBlocks {
    static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(text: paragraph.joined(separator: "\n")))
                paragraph = []
            }
        }

        let lines = source.components(separatedBy: "\n")
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            index += 1

            if trimmed.isEmpty {
                flushParagraph()
            } else if trimmed.hasPrefix("```") {
                flushParagraph()
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[index])
                    index += 1
                }
                index += 1 // skip the closing fence, if there is one
                blocks.append(.code(language: language, text: code.joined(separator: "\n")))
            } else if let heading = headingBlock(trimmed) {
                flushParagraph()
                blocks.append(heading)
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                flushParagraph()
                blocks.append(.bullet(text: String(trimmed.dropFirst(2))))
            } else if let numbered = numberedBlock(trimmed) {
                flushParagraph()
                blocks.append(numbered)
            } else {
                paragraph.append(line)
            }
        }
        flushParagraph()
        return blocks
    }

    /// "## Title" becomes a level-2 heading. Only 1 to 6 hashes followed by a space count.
    private static func headingBlock(_ trimmed: String) -> MarkdownBlock? {
        let hashes = trimmed.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count) else { return nil }
        let rest = trimmed.dropFirst(hashes.count)
        guard rest.first == " " else { return nil }
        return .heading(level: hashes.count, text: rest.dropFirst().trimmingCharacters(in: .whitespaces))
    }

    /// "3. item" becomes a numbered item.
    private static func numberedBlock(_ trimmed: String) -> MarkdownBlock? {
        let digits = trimmed.prefix { $0.isNumber }
        guard !digits.isEmpty, let number = Int(digits) else { return nil }
        let rest = trimmed.dropFirst(digits.count)
        guard rest.hasPrefix(". ") else { return nil }
        return .numbered(number: number, text: String(rest.dropFirst(2)))
    }
}

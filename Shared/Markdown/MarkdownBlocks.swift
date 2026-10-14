//
//  MarkdownBlocks.swift
//  Gatita
//

import Foundation

/// The block-level parts of a chat reply. Inline styling (bold, code, links) stays inside each block's text.
nonisolated enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    /// A bullet, `indent` levels deep (two spaces a level).
    case bullet(text: String, indent: Int = 0)
    /// A numbered item, such as a step of a plan, `indent` levels deep.
    case numbered(number: Int, text: String, indent: Int = 0)
    case code(language: String, text: String)
    /// A pipe table: the header cells, then one list of cells per row. `alignments` is empty unless the separator
    /// row set one with colons, such as |:--|:-:|--:|.
    case table(header: [String], rows: [[String]], alignments: [TableAlignment] = [])
    /// A chart block that holds valid chart data.
    case chart(ChartSpec)
    /// Task lines (- [ ] and - [x]) next to each other, drawn as one checklist with its progress.
    case checklist(items: [ChecklistItem])
    /// A quote (`>`), or a callout such as > [!TIP] when it names a kind.
    case callout(kind: CalloutKind?, text: String)
    /// A line across the reply (---, ***, or ___).
    case rule
}

nonisolated enum TableAlignment: Equatable, Sendable {
    case leading, center, trailing
}

/// The kinds of callout GitHub's Markdown has, which models also write.
nonisolated enum CalloutKind: String, Equatable, Sendable, CaseIterable {
    case note, tip, important, warning, caution
}

/// One line of a checklist.
nonisolated struct ChecklistItem: Equatable, Sendable {
    let done: Bool
    let text: String
    let indent: Int

    /// "2 of 5 done".
    static func progress(_ items: [ChecklistItem]) -> String {
        "\(items.filter(\.done).count) of \(items.count) done"
    }
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
                let body = code.joined(separator: "\n")
                if language == "chart", let spec = ChartSpec.parse(body) {
                    blocks.append(.chart(spec))
                } else {
                    blocks.append(.code(language: language, text: body))
                }
            } else if trimmed.contains("|"), index < lines.count, isSeparator(lines[index]) {
                flushParagraph()
                let header = cells(trimmed)
                let alignments = Self.alignments(lines[index])
                index += 1 // the separator row
                var rows: [[String]] = []
                while index < lines.count, lines[index].contains("|"),
                      !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    rows.append(cells(lines[index]))
                    index += 1
                }
                blocks.append(.table(header: header, rows: rows, alignments: alignments))
            } else if let heading = headingBlock(trimmed) {
                flushParagraph()
                blocks.append(heading)
            } else if isRule(trimmed) {
                flushParagraph()
                blocks.append(.rule)
            } else if let task = taskItem(line) {
                flushParagraph()
                var items = [task]
                while index < lines.count, let next = taskItem(lines[index]) {
                    items.append(next)
                    index += 1
                }
                blocks.append(.checklist(items: items))
            } else if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoted = [String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)]
                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    quoted.append(String(lines[index].trimmingCharacters(in: .whitespaces).dropFirst())
                        .trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(callout(quoted))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                flushParagraph()
                blocks.append(.bullet(text: String(trimmed.dropFirst(2)), indent: indent(of: line)))
            } else if let numbered = numberedBlock(trimmed, indent: indent(of: line)) {
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

    /// "| a | b |" becomes ["a", "b"]. The outer pipes are optional.
    static func cells(_ line: String) -> [String] {
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("|") { text.removeFirst() }
        if text.hasSuffix("|") { text.removeLast() }
        return text.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// The row under a table header: cells made of dashes, with optional colons, such as "|---|:--:|".
    static func isSeparator(_ line: String) -> Bool {
        let parts = cells(line)
        return !parts.isEmpty && parts.allSatisfy { cell in
            let core = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return !core.isEmpty && core.allSatisfy { $0 == "-" }
        }
    }

    /// "3. item" becomes a numbered item.
    private static func numberedBlock(_ trimmed: String, indent: Int) -> MarkdownBlock? {
        let digits = trimmed.prefix { $0.isNumber }
        guard !digits.isEmpty, let number = Int(digits) else { return nil }
        let rest = trimmed.dropFirst(digits.count)
        guard rest.hasPrefix(". ") else { return nil }
        return .numbered(number: number, text: String(rest.dropFirst(2)), indent: indent)
    }

    /// How deep a list line is: two spaces (or one tab) a level, at most four levels.
    private static func indent(of line: String) -> Int {
        var width = 0
        for character in line {
            if character == " " { width += 1 } else if character == "\t" { width += 2 } else { break }
        }
        return min(width / 2, 4)
    }

    /// "- [ ] text" or "- [x] text" (also with * or +), as a checklist item.
    private static func taskItem(_ line: String) -> ChecklistItem? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 6, ["- [", "* [", "+ ["].contains(String(trimmed.prefix(3))) else { return nil }
        let mark = trimmed[trimmed.index(trimmed.startIndex, offsetBy: 3)]
        guard [" ", "x", "X"].contains(mark), trimmed.dropFirst(4).hasPrefix("] ") else { return nil }
        return ChecklistItem(done: mark != " ", text: String(trimmed.dropFirst(6)), indent: indent(of: line))
    }

    /// Three or more of the same mark (-, *, or _), with spaces allowed between them.
    private static func isRule(_ trimmed: String) -> Bool {
        let marks = trimmed.filter { $0 != " " }
        guard marks.count >= 3, let first = marks.first, "-*_".contains(first) else { return false }
        return marks.allSatisfy { $0 == first }
    }

    /// The quoted lines as a callout when the first names a kind (> [!TIP]), otherwise as a quote.
    private static func callout(_ quoted: [String]) -> MarkdownBlock {
        var lines = quoted
        if let first = lines.first, first.hasPrefix("[!"), let close = first.firstIndex(of: "]") {
            let name = first[first.index(first.startIndex, offsetBy: 2)..<close].lowercased()
            if let kind = CalloutKind(rawValue: name) {
                let rest = first[first.index(after: close)...].trimmingCharacters(in: .whitespaces)
                lines.removeFirst()
                if !rest.isEmpty { lines.insert(rest, at: 0) }
                return .callout(kind: kind, text: lines.joined(separator: "\n"))
            }
        }
        return .callout(kind: nil, text: lines.joined(separator: "\n"))
    }

    /// The column alignments a separator row sets with colons, or none when it sets no colon at all.
    private static func alignments(_ separator: String) -> [TableAlignment] {
        let parts = cells(separator)
        guard parts.contains(where: { $0.contains(":") }) else { return [] }
        return parts.map { cell in
            switch (cell.hasPrefix(":"), cell.hasSuffix(":")) {
            case (true, true): .center
            case (false, true): .trailing
            default: .leading
            }
        }
    }
}

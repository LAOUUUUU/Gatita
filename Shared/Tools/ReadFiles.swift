//
//  ReadFiles.swift
//  Gatita
//

import Foundation

/// The text side of read_files: the list of paths, and one file's section of the Markdown document it returns.
nonisolated enum ReadFiles {
    /// The most files one call reads, and the most characters of file text it returns in all.
    static let maxFiles = 20
    static let maxCharacters = 100_000

    /// The paths in the argument, in order, without blanks or repeats. One path per line is the usual form.
    /// A single line may hold several paths separated by commas.
    static func pathList(_ text: String) -> [String] {
        let lines = text.components(separatedBy: .newlines)
        let parts = lines.count > 1 ? lines : text.components(separatedBy: ",")
        var seen = Set<String>()
        var paths: [String] = []
        for part in parts {
            let path = part.trimmingCharacters(in: .whitespaces)
            if !path.isEmpty, seen.insert(path).inserted {
                paths.append(path)
            }
        }
        return paths
    }

    /// A backtick fence one longer than the longest run of backticks in the text, and at least three,
    /// so a file that holds a fence of its own can't close this one early.
    static func fence(for text: String) -> String {
        var longest = 0
        var current = 0
        for character in text {
            if character == "`" {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
        }
        return String(repeating: "`", count: max(3, longest + 1))
    }

    /// One file under its path: a heading, then its text in a fence named after its extension, between a line that
    /// marks where it starts and one that marks where it ends, so the model never mixes up two files.
    static func section(path: String, text: String) -> String {
        guard !text.isEmpty else { return "## \(path)\n\n(empty file)" }
        let fence = fence(for: text)
        let language = URL(fileURLWithPath: path).pathExtension.filter { $0.isLetter || $0.isNumber }
        let body = text.hasSuffix("\n") ? String(text.dropLast()) : text
        return "## \(path)\n\n===== start of \(path) =====\n\(fence)\(language)\n\(body)\n\(fence)\n===== end of \(path) ====="
    }

    /// Whether an entry is a pattern such as "Shared/*.swift" or "**/*.md" rather than one path.
    static func isPattern(_ entry: String) -> Bool {
        entry.contains("*") || entry.contains("?") || entry.contains("[")
    }

    /// A path as a pattern that matches only itself: *, ?, [, ], and \\ get a backslash.
    static func escaped(_ path: String) -> String {
        path.reduce(into: "") { result, character in
            if "*?[]\\".contains(character) { result.append("\\") }
            result.append(character)
        }
    }

    /// Whether a pattern can be used at all. An unclosed [ or a stray ] makes it invalid.
    static func isValidPattern(_ pattern: String) -> Bool {
        (try? NSRegularExpression(pattern: regex(for: pattern))) != nil
    }

    /// Whether a project-relative path matches a glob: "*" and "?" stay inside one folder, and "**" crosses folders.
    static func matches(_ path: String, pattern: String) -> Bool {
        // A pattern that does not make a valid expression matches nothing.
        guard let expression = try? NSRegularExpression(pattern: regex(for: pattern)) else { return false }
        return expression.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)) != nil
    }

    private static func regex(for glob: String) -> String {
        var result = "^"
        var characters = Array(glob)[...]
        var literalBuffer = ""
        func flushLiteral() {
            if !literalBuffer.isEmpty {
                result += NSRegularExpression.escapedPattern(for: literalBuffer)
                literalBuffer = ""
            }
        }
        while let character = characters.popFirst() {
            switch character {
            case "\\":
                // A backslash makes the next character plain.
                literalBuffer.append(characters.popFirst() ?? "\\")
            case "*" where characters.first == "*":
                flushLiteral()
                characters.removeFirst()
                if characters.first == "/" {
                    characters.removeFirst()
                    result += "(?:.*/)?"
                } else {
                    result += ".*"
                }
            case "*":
                flushLiteral()
                result += "[^/]*"
            case "?":
                flushLiteral()
                result += "[^/]"
            case "[":
                flushLiteral()
                result += "["
            case "]":
                flushLiteral()
                result += "]"
            default:
                literalBuffer.append(character)
            }
        }
        flushLiteral()
        return result + "$"
    }

    /// A file that was not read: a heading and the reason.
    static func section(path: String, note: String) -> String {
        "## \(path)\n\n\(note)"
    }
}
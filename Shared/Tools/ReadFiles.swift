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

    /// One file under its path: a heading, then its text in a fence named after its extension.
    static func section(path: String, text: String) -> String {
        guard !text.isEmpty else { return "## \(path)\n\n(empty file)" }
        let fence = fence(for: text)
        let language = URL(fileURLWithPath: path).pathExtension.filter { $0.isLetter || $0.isNumber }
        let body = text.hasSuffix("\n") ? String(text.dropLast()) : text
        return "## \(path)\n\n\(fence)\(language)\n\(body)\n\(fence)"
    }

    /// A file that was not read: a heading and the reason.
    static func section(path: String, note: String) -> String {
        "## \(path)\n\n\(note)"
    }
}

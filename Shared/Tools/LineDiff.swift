//
//  LineDiff.swift
//  Gatita
//

import Foundation

/// One line of a diff: unchanged, added, or removed.
nonisolated struct DiffLine: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case same
        case added
        case removed
    }

    let kind: Kind
    let text: String
}

/// A change Gatita made to one file: the path, and the lines that differ with a little context around them.
nonisolated struct FileChange: Codable, Hashable, Sendable {
    let path: String
    let lines: [DiffLine]

    var added: Int { lines.filter { $0.kind == .added }.count }
    var removed: Int { lines.filter { $0.kind == .removed }.count }
}

/// Line-by-line differences between two versions of a file.
nonisolated enum LineDiff {
    /// Unchanged lines kept on each side of a change.
    static let context = 3
    /// Above this many cells in the comparison table, the middle part is shown as all removed, then all added.
    static let maxCells = 4_000_000

    static func lines(from old: String, to new: String) -> [DiffLine] {
        let a = split(old)
        let b = split(new)

        var start = 0
        while start < a.count, start < b.count, a[start] == b[start] {
            start += 1
        }
        var endA = a.count
        var endB = b.count
        while endA > start, endB > start, a[endA - 1] == b[endB - 1] {
            endA -= 1
            endB -= 1
        }
        guard start < endA || start < endB else { return [] }

        var result = a[max(0, start - context)..<start].map { DiffLine(kind: .same, text: $0) }
        result += middle(Array(a[start..<endA]), Array(b[start..<endB]))
        result += a[endA..<min(a.count, endA + context)].map { DiffLine(kind: .same, text: $0) }
        return result
    }

    /// The part that differs, compared line by line with the longest common run kept as unchanged.
    private static func middle(_ a: [String], _ b: [String]) -> [DiffLine] {
        if a.isEmpty { return b.map { DiffLine(kind: .added, text: $0) } }
        if b.isEmpty { return a.map { DiffLine(kind: .removed, text: $0) } }
        guard (a.count + 1) * (b.count + 1) <= maxCells else {
            return a.map { DiffLine(kind: .removed, text: $0) } + b.map { DiffLine(kind: .added, text: $0) }
        }

        let width = b.count + 1
        var table = [Int](repeating: 0, count: (a.count + 1) * width)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i * width + j] = a[i] == b[j]
                    ? table[(i + 1) * width + j + 1] + 1
                    : max(table[(i + 1) * width + j], table[i * width + j + 1])
            }
        }

        var result: [DiffLine] = []
        var i = 0
        var j = 0
        while i < a.count, j < b.count {
            if a[i] == b[j] {
                result.append(DiffLine(kind: .same, text: a[i]))
                i += 1
                j += 1
            } else if table[(i + 1) * width + j] >= table[i * width + j + 1] {
                result.append(DiffLine(kind: .removed, text: a[i]))
                i += 1
            } else {
                result.append(DiffLine(kind: .added, text: b[j]))
                j += 1
            }
        }
        result += a[i...].map { DiffLine(kind: .removed, text: $0) }
        result += b[j...].map { DiffLine(kind: .added, text: $0) }
        return result
    }

    /// The lines of a file. A trailing newline does not start an extra empty line.
    private static func split(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var lines = text.components(separatedBy: "\n")
        if text.hasSuffix("\n") {
            lines.removeLast()
        }
        return lines
    }
}

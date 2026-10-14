//
//  TableChart.swift
//  Gatita
//

import Foundation

/// A table drawn as a chart: the first column gives the labels, and the first column after it whose cells are all
/// numbers gives the values. "$1,200", "1 800", "2.5k", and "42%" all count as numbers.
nonisolated enum TableChart {
    static func spec(header: [String], rows: [[String]]) -> ChartSpec? {
        guard rows.count >= 2, rows.count <= ChartSpec.maxPoints, header.count >= 2 else { return nil }
        for column in 1..<header.count {
            let values = rows.map { row in column < row.count ? number(row[column]) : nil }
            guard values.allSatisfy({ $0 != nil }) else { continue }
            let points = zip(rows, values).map { row, value in
                ChartSpec.Point(label: row.first.map(plain) ?? "", value: value ?? 0)
            }
            let percent = rows.allSatisfy { column < $0.count && $0[column].contains("%") }
            let type = rows.count > 12 || percent ? "line" : "bar"
            return ChartSpec(type: type, title: "\(plain(header[column])) by \(plain(header[0]))", points: points)
        }
        return nil
    }

    /// A cell as a number, ignoring currency signs, thousands separators, spaces, bold marks, and a k or m suffix.
    static func number(_ cell: String) -> Double? {
        var text = plain(cell).lowercased()
        for mark in ["$", "€", "£", "¥", ",", " ", "%", "+"] { text = text.replacingOccurrences(of: mark, with: "") }
        var scale = 1.0
        if text.hasSuffix("k") { scale = 1_000; text.removeLast() } else if text.hasSuffix("m") { scale = 1_000_000; text.removeLast() }
        text = text.replacingOccurrences(of: "−", with: "-")
        guard !text.isEmpty, let value = Double(text) else { return nil }
        return value * scale
    }

    /// A cell without Markdown emphasis marks.
    private static func plain(_ cell: String) -> String {
        cell.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}

/// What every reply is told about how the chat draws Markdown, so the model makes tables, charts, checklists, and
/// callouts when they help instead of only plain text.
nonisolated enum ReplyFormat {
    static let instructions = """
        This chat draws Markdown. When it helps the reader, use: headings and short paragraphs; numbered lists for steps; task lists (- [ ] to do, - [x] done) for plans and to-dos; Markdown tables to compare things; callouts such as > [!TIP], > [!NOTE], or > [!WARNING] for the one thing not to miss; and to show numbers as a graph, a fenced block that opens with ```chart and holds one JSON object: {"type": "bar" or "line" or "pie", "title": "...", "points": [{"label": "...", "value": 12.5}]} with at most 50 points. Keep plain answers plain.
        """

    /// The format note, then the other instructions (yours and the skill's), if any.
    static func system(with other: String?) -> String {
        guard let other, !other.isEmpty else { return instructions }
        return instructions + "\n\n" + other
    }
}

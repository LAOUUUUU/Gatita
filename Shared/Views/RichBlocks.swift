//
//  RichBlocks.swift
//  Gatita
//

import SwiftUI

/// Inline Markdown (bold, italic, code, links) inside one block's text.
enum InlineMarkdown {
    /// The text, with the ⌘F words marked when `highlight` is not empty.
    static func text(_ source: String, highlight: String = "") -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let parsed = (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
        return Text(FindInChat.highlighted(parsed, query: highlight))
    }
}

/// A plan or to-do list: a progress bar, then each task with a check. Done tasks are struck through.
struct ChecklistView: View {
    let items: [ChecklistItem]
    @Environment(\.findHighlight) private var findHighlight

    var body: some View {
        let done = items.filter(\.done).count
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "checklist")
                    .foregroundStyle(Theme.accent)
                Text(ChecklistItem.progress(items))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ProgressView(value: Double(done), total: Double(max(items.count, 1)))
                    .tint(Theme.accent)
                    .frame(maxWidth: 140)
            }
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.done ? Theme.accent : .secondary)
                    InlineMarkdown.text(item.text, highlight: findHighlight)
                        .strikethrough(item.done, color: .secondary)
                        .foregroundStyle(item.done ? .secondary : .primary)
                }
                .padding(.leading, CGFloat(item.indent) * 22)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.1)))
    }
}

/// A callout (> [!TIP] and friends) with its color, icon, and name, or a plain quote in gray.
struct CalloutView: View {
    let kind: CalloutKind?
    let text: String
    @Environment(\.findHighlight) private var findHighlight

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                if let kind {
                    Label(Self.title(kind), systemImage: Self.icon(kind))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(color)
                }
                InlineMarkdown.text(text, highlight: findHighlight)
                    .foregroundStyle(kind == nil ? .secondary : .primary)
                    .italic(kind == nil)
            }
        }
        .padding(kind == nil ? 4 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(kind == nil ? .clear : color.opacity(0.1)))
    }

    private var color: Color {
        switch kind {
        case .note: Color(red: 0.4, green: 0.65, blue: 1)
        case .tip: Color(red: 0.35, green: 0.8, blue: 0.45)
        case .important: Color(red: 0.7, green: 0.5, blue: 1)
        case .warning: Theme.accent
        case .caution: Color(red: 1, green: 0.4, blue: 0.4)
        case nil: Color.white.opacity(0.3)
        }
    }

    static func title(_ kind: CalloutKind) -> String {
        kind.rawValue.prefix(1).uppercased() + kind.rawValue.dropFirst()
    }

    static func icon(_ kind: CalloutKind) -> String {
        switch kind {
        case .note: "info.circle.fill"
        case .tip: "lightbulb.fill"
        case .important: "exclamationmark.bubble.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .caution: "xmark.octagon.fill"
        }
    }
}

/// A numbered item. Top-level steps get an orange number badge, so a plan reads as steps.
struct StepView: View {
    let number: Int
    let text: String
    let indent: Int
    @Environment(\.findHighlight) private var findHighlight

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if indent == 0 {
                Text("\(number)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.accent)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(Circle().fill(Theme.accent.opacity(0.16)))
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 5 }
            } else {
                Text("\(number).")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            InlineMarkdown.text(text, highlight: findHighlight)
        }
        .padding(.leading, CGFloat(indent) * 22)
    }
}

/// A table in a card: the header on a tinted row, striped rows, each column aligned as the Markdown said, and a
/// bar with Copy and, when a column holds numbers, a switch to see it as a chart.
struct MarkdownTableView: View {
    let header: [String]
    let rows: [[String]]
    let alignments: [TableAlignment]
    @Environment(\.findHighlight) private var findHighlight
    @State private var asChart = false
    @State private var copied = false

    var body: some View {
        let chart = TableChart.spec(header: header, rows: rows)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(rows.count == 1 ? "1 row" : "\(rows.count) rows")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if chart != nil {
                    HStack(spacing: 2) {
                        viewButton("tablecells", chart: false, help: "See it as a table")
                        viewButton("chart.bar.xaxis", chart: true, help: "See it as a chart")
                    }
                    .padding(2)
                    .background(Capsule().fill(Theme.surface))
                }
                Button {
                    Clipboard.copy(markdown)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(copied ? Theme.accent : .secondary)
                }
                .buttonStyle(.plain)
                .help("Copy the table as Markdown")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.045))

            if asChart, let chart {
                ChartBlockView(spec: chart)
                    .padding(8)
            } else {
                grid
            }
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.1)))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// One half of the table and chart switch: orange when it is the view on screen.
    private func viewButton(_ icon: String, chart: Bool, help: String) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { asChart = chart }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(asChart == chart ? Color.white : .secondary)
                .frame(width: 30, height: 22)
                .background(Capsule().fill(asChart == chart ? Theme.accent : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var columns: Int { max(header.count, rows.map(\.count).max() ?? 0) }

    private func padded(_ cells: [String]) -> [String] {
        (0..<columns).map { $0 < cells.count ? cells[$0] : "" }
    }

    private func alignment(_ column: Int) -> Alignment {
        guard column < alignments.count else { return .leading }
        switch alignments[column] {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    /// The table across the whole card when it fits, and scrolling sideways when it is wider than the card.
    private var grid: some View {
        ViewThatFits(in: .horizontal) {
            table
            ScrollView(.horizontal) { table.fixedSize(horizontal: true, vertical: false) }
        }
    }

    private var table: some View {
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(padded(header).enumerated()), id: \.offset) { column, cell in
                        InlineMarkdown.text(cell, highlight: findHighlight)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, alignment: alignment(column))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                }
                .background(Theme.accent.opacity(0.1))
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    GridRow {
                        ForEach(Array(padded(row).enumerated()), id: \.offset) { column, cell in
                            InlineMarkdown.text(cell, highlight: findHighlight)
                                .frame(maxWidth: .infinity, alignment: alignment(column))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                        }
                    }
                    .background(index.isMultiple(of: 2) ? Color.clear : Color.white.opacity(0.035))
                }
        }
    }

    /// The table as Markdown, for Copy.
    private var markdown: String {
        let line = { (cells: [String]) in "| " + cells.joined(separator: " | ") + " |" }
        let rule = "|" + String(repeating: " --- |", count: columns)
        return ([line(padded(header)), rule] + rows.map { line(padded($0)) }).joined(separator: "\n")
    }
}

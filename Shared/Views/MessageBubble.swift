//
//  MessageBubble.swift
//  Gatita
//
//  Created by LAOUUU on 2026-10-08.
//


import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage
    /// What to show besides the text. The default shows everything, as before.
    var transcriptView: TranscriptView = .verbose
    /// Runs a button under a reply. Nil hides the buttons.
    var onAction: ((MessageAction) -> Void)? = nil

    var body: some View {
        if message.role == "error" {
            errorBubble
        } else if message.role == "notice" {
            Text(message.content)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if message.role == "user" {
            VStack(alignment: .trailing, spacing: 6) {
                if !message.attachedImages.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(message.attachedImages.enumerated()), id: \.offset) { _, image in
                            ImageThumbnail(data: image.data, side: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                if !message.content.isEmpty {
                    Text(message.content)
                        .padding(10)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
                }
            }
            .frame(maxWidth: 560, alignment: .trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            assistantBubble
        }
    }

    /// A red bubble for something that went wrong. The detail, if any, is what the server or the system gave.
    private var errorBubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.content)
                .font(.callout.weight(.semibold))
            if let detail = message.errorText {
                Text(detail)
                    .font(.callout)
            }
        }
        .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.45))
        .padding(12)
        .frame(maxWidth: 560, alignment: .leading)
        .background(Color.red.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.red.opacity(0.35)))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var assistantBubble: some View {
        let streaming = message.isStreaming
        let hasText = !message.content.isEmpty
        let showThinking = transcriptView.showsThinking && (!message.reasoning.isEmpty || (streaming && !hasText))

        return VStack(alignment: .leading, spacing: 8) {
            if showThinking {
                ThinkingView(text: message.reasoning, isLive: streaming && !hasText,
                             startsExpanded: transcriptView.expandsThinking)
            }
            if transcriptView.showsToolCalls {
                ForEach(message.activities) { activity in
                    ToolActivityRow(activity: activity, expanded: transcriptView.expandsToolCalls)
                }
            }
            if hasText {
                MarkdownText(source: message.content)
            }
            if streaming && hasText {
                WaveDots(size: 5)
            }
            if let errorText = message.errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let usage = message.usage, !streaming {
                Text(usage.summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            actionRow
            if let respondedAt = message.respondedAt, !streaming {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(ReplyTime.label(since: respondedAt, now: context.date))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Copy, fork, pin, and reply under a finished reply. A pinned reply shows a filled pin.
    @ViewBuilder
    private var actionRow: some View {
        if let onAction, !message.isStreaming, !message.content.isEmpty {
            let pinned = message.pinned == true
            HStack(spacing: 4) {
                actionButton("doc.on.doc", "Copy", .copy, onAction)
                actionButton("arrow.triangle.branch", "Fork a new chat from here", .fork, onAction)
                actionButton(pinned ? "pin.fill" : "pin", pinned ? "Unpin" : "Pin", .pin, onAction)
                actionButton("arrowshape.turn.up.left", "Reply to this", .reply, onAction)
            }
            .padding(.top, 4)
        }
    }

    private func actionButton(_ icon: String, _ help: String, _ action: MessageAction,
                              _ perform: @escaping (MessageAction) -> Void) -> some View {
        Button {
            perform(action)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Renders a reply's Markdown: headings, bullets, numbered items, code blocks, and inline bold, italic, and code.
struct MarkdownText: View {
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MarkdownBlocks.parse(source).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            inline(text)
                .font(headingFont(level))
                .fontWeight(.semibold)
        case .paragraph(let text):
            inline(text)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•")
                inline(text)
            }
        case .numbered(let number, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(number).")
                    .monospacedDigit()
                inline(text)
            }
        case .code(_, let text):
            ScrollView(.horizontal) {
                Text(text)
                    .font(.system(.callout, design: .monospaced))
                    .padding(8)
            }
            .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
        case .table(let header, let rows):
            tableView(header: header, rows: rows)
        case .chart(let spec):
            ChartBlockView(spec: spec)
        }
    }

    /// A table with a bold header, a rule under it, and a border. Short rows are padded with empty cells.
    private func tableView(header: [String], rows: [[String]]) -> some View {
        let columns = max(header.count, rows.map(\.count).max() ?? 0)
        func padded(_ cells: [String]) -> [String] {
            (0..<columns).map { $0 < cells.count ? cells[$0] : "" }
        }
        return ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                GridRow {
                    ForEach(Array(padded(header).enumerated()), id: \.offset) { _, cell in
                        inline(cell).fontWeight(.semibold)
                    }
                }
                Divider()
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(padded(row).enumerated()), id: \.offset) { _, cell in
                            inline(cell)
                        }
                    }
                }
            }
            .padding(10)
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.12)))
    }

    private func inline(_ text: String) -> Text {
        Text(attributed(text))
    }

    private func attributed(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2
        case 2: return .title3
        case 3: return .headline
        default: return .subheadline
        }
    }
}

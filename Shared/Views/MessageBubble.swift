//
//  MessageBubble.swift
//  Gatita
//
//  Created by LAOUUU on 2026-10-08.
//


import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        if message.role == "user" {
            Text(message.content)
                .padding(10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
                .frame(maxWidth: 560, alignment: .trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            assistantBubble
        }
    }

    private var assistantBubble: some View {
        let streaming = message.isStreaming
        let hasText = !message.content.isEmpty
        let showThinking = !message.reasoning.isEmpty || (streaming && !hasText)

        return VStack(alignment: .leading, spacing: 8) {
            if showThinking {
                ThinkingView(text: message.reasoning, isLive: streaming && !hasText)
            }
            ForEach(message.activities) { activity in
                ToolActivityRow(activity: activity)
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        }
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

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
        if message.role == "error" {
            errorBubble
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

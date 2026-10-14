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
    /// Runs a button under a message. Nil hides the buttons.
    var onAction: ((MessageAction) -> Void)? = nil
    /// True while this reply is being read aloud.
    var isSpeaking = false
    /// True while any reply is on its way, when a question can't be edited or a reply regenerated.
    var isBusy = false
    /// True when the files this reply wrote or edited can be put back.
    var canUndo = false
    @State private var isEditing = false
    /// The ⌘F words, marked in a question's text.
    @Environment(\.findHighlight) private var findHighlight
    @State private var editText = ""
    @State private var hovering = false

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
                if isEditing {
                    editor
                } else if !message.content.isEmpty {
                    Text(FindInChat.highlighted(AttributedString(message.content), query: findHighlight))
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                questionActions
            }
            .frame(maxWidth: 560, alignment: .trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
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

    /// The box a question is edited in, with Cancel and Send. Sending replaces the question and what came after it.
    private var editor: some View {
        VStack(alignment: .trailing, spacing: 8) {
            TextField("Edit your message", text: $editText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...12)
                .padding(12)
                .frame(minWidth: 280)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.accent.opacity(0.6)))
                .onSubmit(sendEdit)
            HStack(spacing: 8) {
                Button("Cancel") { isEditing = false }
                    .buttonStyle(GatitaButtonStyle(.secondary))
                    .keyboardShortcut(.cancelAction)
                Button("Send", action: sendEdit)
                    .buttonStyle(GatitaButtonStyle(.primary))
                    .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBusy)
            }
        }
    }

    private func sendEdit() {
        guard !isBusy else { return }
        isEditing = false
        onAction?(.edit(editText))
    }

    /// Copy and edit under a question. On a Mac they show while the pointer is over it.
    @ViewBuilder
    private var questionActions: some View {
        #if os(macOS)
        let visible = hovering
        #else
        let visible = true
        #endif
        if let onAction, !isEditing, !message.content.isEmpty {
            HStack(spacing: 2) {
                actionButton("doc.on.doc", "Copy", .copy, onAction)
                Button {
                    editText = message.content
                    isEditing = true
                } label: {
                    actionIcon("pencil")
                }
                .buttonStyle(.plain)
                .help("Edit and send again")
                .disabled(isBusy)
            }
            .opacity(visible ? 1 : 0)
            .animation(.easeOut(duration: 0.15), value: visible)
        }
    }

    /// Copy, read aloud, regenerate, fork, pin, and reply under a finished reply. A pinned reply shows a filled pin.
    @ViewBuilder
    private var actionRow: some View {
        if let onAction, !message.isStreaming, !message.content.isEmpty {
            let pinned = message.pinned == true
            HStack(spacing: 4) {
                actionButton("doc.on.doc", "Copy", .copy, onAction)
                actionButton(isSpeaking ? "stop.circle" : "speaker.wave.2", isSpeaking ? "Stop reading" : "Read aloud",
                             .speak, onAction, tint: isSpeaking ? Theme.accent : nil)
                GatitaMenuButton(id: "regenerate-\(message.id)", title: "Regenerate", alignTrailing: false, items: {
                    [GatitaMenuItem(title: "Regenerate", subtitle: "With the model chosen now", icon: "arrow.clockwise") {
                        onAction(.regenerate(model: nil))
                    }] + ChatViewModel.models.enumerated().map { index, model in
                        GatitaMenuItem(title: "With \(ChatViewModel.displayName(for: model))", icon: "cpu",
                                       startsSection: index == 0) { onAction(.regenerate(model: model)) }
                    }
                }) {
                    actionIcon("arrow.clockwise")
                }
                .disabled(isBusy)
                .help("Regenerate")
                if canUndo {
                    actionButton("arrow.uturn.backward", "Undo this reply's file changes (changes made by commands are not undone)",
                                 .undoChanges, onAction)
                        .disabled(isBusy)
                }
                actionButton("arrow.triangle.branch", "Fork a new chat from here", .fork, onAction)
                actionButton(pinned ? "pin.fill" : "pin", pinned ? "Unpin" : "Pin", .pin, onAction)
                actionButton("arrowshape.turn.up.left", "Reply to this", .reply, onAction)
            }
            .padding(.top, 4)
        }
    }

    private func actionIcon(_ icon: String, tint: Color? = nil) -> some View {
        Image(systemName: icon)
            .font(.system(size: 13))
            .foregroundStyle(tint ?? .secondary)
            .frame(width: 26, height: 26)
            .contentShape(Rectangle())
    }

    private func actionButton(_ icon: String, _ help: String, _ action: MessageAction,
                              _ perform: @escaping (MessageAction) -> Void, tint: Color? = nil) -> some View {
        Button {
            perform(action)
        } label: {
            actionIcon(icon, tint: tint)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Renders a reply's Markdown: headings, nested lists, numbered steps, checklists, callouts, tables (which can turn
/// into charts), charts, code, rules, and inline bold, italic, and code.
struct MarkdownText: View {
    let source: String
    /// The ⌘F words, marked in the text.
    @Environment(\.findHighlight) private var findHighlight

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
            textOrMath(text)
        case .bullet(let text, let indent):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(["•", "◦", "–"][indent % 3])
                    .foregroundStyle(indent == 0 ? Theme.accent : .secondary)
                textOrMath(text)
            }
            .padding(.leading, CGFloat(indent) * 22)
        case .numbered(let number, let text, let indent):
            StepView(number: number, text: text, indent: indent)
        case .code(let language, let text):
            switch RichCode.kind(language: language) {
            case .diagram:
                MermaidBlockView(code: text)
            case .math:
                MathBlockView(code: text)
            case .code:
                CodeBlockView(language: language, code: text)
                    .equatable()
            }
        case .table(let header, let rows, let alignments):
            MarkdownTableView(header: header, rows: rows, alignments: alignments)
        case .chart(let spec):
            ChartBlockView(spec: spec)
        case .checklist(let items):
            ChecklistView(items: items)
        case .callout(let kind, let text):
            CalloutView(kind: kind, text: text)
        case .rule:
            Divider()
                .overlay(Color.white.opacity(0.12))
                .padding(.vertical, 4)
        }
    }

    /// Text with math in it is drawn with LaTeX; anything else stays plain Markdown text.
    @ViewBuilder
    private func textOrMath(_ text: String) -> some View {
        if MathDetection.containsMath(text) {
            MathText(text: text)
        } else {
            inline(text)
        }
    }

    private func inline(_ text: String) -> Text {
        Text(FindInChat.highlighted(attributed(text), query: findHighlight))
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

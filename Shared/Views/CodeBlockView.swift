//
//  CodeBlockView.swift
//  Gatita
//

import SwiftUI

/// A code block in a reply: the language and a copy button on top, and the code in color below.
/// Equatable, so while a reply streams, blocks above the one growing are not colored again on each new word.
struct CodeBlockView: View, Equatable {
    let language: String
    let code: String
    @State private var copied = false
    @State private var previewing = false

    /// Past this size the code is shown without colors, so a huge block stays quick to draw.
    private static let maxColoredCharacters = 30_000

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(SyntaxHighlighter.displayName(language))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if HTMLPreview.canPreview(language: language, code: code) {
                    Button {
                        previewing = true
                    } label: {
                        Label("Preview", systemImage: "play.rectangle")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .help("Show this page live, with the network blocked")
                }
                Button(action: copy) {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(copied ? Theme.accent : .secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .help("Copy this code")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.045))

            ScrollView(.horizontal) {
                Text(colored)
                    .font(.system(.callout, design: .monospaced))
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(12)
            }
            .scrollIndicators(.automatic)
        }
        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.08)))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .sheet(isPresented: $previewing) {
            HTMLPreviewSheet(language: language, code: code)
                .presentationBackground(Theme.background)
        }
    }

    private var colored: AttributedString {
        guard code.count <= Self.maxColoredCharacters else { return AttributedString(code) }
        var result = AttributedString()
        for token in SyntaxHighlighter.tokens(code, language: language) {
            var piece = AttributedString(token.text)
            piece.foregroundColor = Self.color(token.kind)
            if token.kind == .comment { piece.inlinePresentationIntent = .emphasized }
            result += piece
        }
        return result
    }

    /// Gatita's colors for code: the orange accent for keywords, soft colors for the rest.
    static func color(_ kind: SyntaxHighlighter.Kind) -> Color {
        switch kind {
        case .keyword: Theme.accent
        case .type: Color(red: 0.45, green: 0.78, blue: 0.95)
        case .string: Color(red: 0.64, green: 0.85, blue: 0.52)
        case .number: Color(red: 0.88, green: 0.76, blue: 0.45)
        case .comment: Color.white.opacity(0.42)
        case .plain: Color.white.opacity(0.9)
        }
    }

    static func == (lhs: CodeBlockView, rhs: CodeBlockView) -> Bool {
        lhs.language == rhs.language && lhs.code == rhs.code
    }

    private func copy() {
        Clipboard.copy(code)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

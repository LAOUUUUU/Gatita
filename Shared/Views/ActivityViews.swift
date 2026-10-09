//
//  ActivityViews.swift
//  Gatita
//

import SwiftUI

/// Three dots that rise in a wave, shown while Gatita is working.
struct WaveDots: View {
    var size: CGFloat = 7

    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: size * 0.6) {
                ForEach(0..<3, id: \.self) { index in
                    let lift = max(0, sin(time * 6 - Double(index) * 0.9)) * size * 0.9
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: size, height: size)
                        .offset(y: -lift)
                }
            }
            .frame(height: size * 2)
        }
        .accessibilityLabel("Gatita is working")
    }
}

/// Collapsible block with the model's thinking. Shows the wave while thinking is still streaming.
struct ThinkingView: View {
    let text: String
    let isLive: Bool

    var body: some View {
        DisclosureGroup {
            if !text.isEmpty {
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        } label: {
            HStack(spacing: 6) {
                Text(isLive ? "Thinking" : "Thought process")
                    .font(.callout.weight(.medium))
                if isLive {
                    WaveDots(size: 4)
                }
            }
        }
    }
}

/// One tool call: the name and arguments, a spinner while it runs, and the result when expanded.
struct ToolActivityRow: View {
    let activity: ToolActivity
    /// A file change opens with its diff showing.
    @State private var expanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            if let change = activity.change {
                DiffView(change: change)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(activity.arguments)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    if let result = activity.result {
                        Text(String(result.prefix(4000)))
                            .font(.caption.monospaced())
                    }
                }
                .textSelection(.enabled)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: activity.result == nil ? "gearshape.2" : "checkmark.circle")
                    .foregroundStyle(activity.result == nil ? Color.secondary : Color.green)
                Text(activity.name)
                    .font(.callout.monospaced())
                if let change = activity.change {
                    Text(change.path)
                        .font(.caption.monospaced())
                    Text("+\(change.added)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.green)
                    Text("−\(change.removed)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.red)
                } else {
                    Text(activity.arguments)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if activity.result == nil {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }
}


/// A file change as an IDE shows it: the path, the counts, and the changed lines in red and green.
struct DiffView: View {
    let change: FileChange
    /// Long diffs stop here, with a note on how many lines were left out.
    private static let maxLines = 400

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .foregroundStyle(Theme.accent)
                Text(change.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                countPill("+\(change.added)", color: .green)
                countPill("−\(change.removed)", color: .red)
            }
            .font(.caption.monospaced())
            .foregroundStyle(.white.opacity(0.85))
            .padding(10)
            .background(Color.white.opacity(0.05))

            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(change.lines.prefix(Self.maxLines).enumerated()), id: \.offset) { _, line in
                        DiffRow(line: line)
                    }
                    if change.lines.count > Self.maxLines {
                        Text("… \(change.lines.count - Self.maxLines) more lines")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .padding(6)
                    }
                }
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 360)
        }
        .textSelection(.enabled)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08)))
    }

    private func countPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.monospaced().weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.14)))
    }
}

/// One line of a diff, with its sign and a tint for added or removed lines.
private struct DiffRow: View {
    let line: DiffLine

    private var sign: String {
        switch line.kind {
        case .same: " "
        case .added: "+"
        case .removed: "−"
        }
    }

    private var tint: Color {
        switch line.kind {
        case .same: .clear
        case .added: Color.green.opacity(0.16)
        case .removed: Color.red.opacity(0.16)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(sign)
                .frame(width: 12, alignment: .center)
                .foregroundStyle(line.kind == .added ? Color.green : line.kind == .removed ? Color.red : Color.secondary)
            Text(line.text.isEmpty ? " " : line.text)
                .foregroundStyle(.white.opacity(0.88))
        }
        .font(.caption.monospaced())
        .padding(.horizontal, 10)
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint)
    }
}

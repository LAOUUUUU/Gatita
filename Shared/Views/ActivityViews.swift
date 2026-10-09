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

    var body: some View {
        DisclosureGroup {
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
        } label: {
            HStack(spacing: 6) {
                Image(systemName: activity.result == nil ? "gearshape.2" : "checkmark.circle")
                    .foregroundStyle(activity.result == nil ? Color.secondary : Color.green)
                Text(activity.name)
                    .font(.callout.monospaced())
                Text(activity.arguments)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if activity.result == nil {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }
}

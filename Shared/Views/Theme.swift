//
//  Theme.swift
//  Gatita
//

import SwiftUI

/// Colors for the dark look: near-black background, orange accent, and a lighter surface for panels and the prompt box.
enum Theme {
    static let accent = Color(red: 0.96, green: 0.42, blue: 0.14)
    static let background = Color(white: 0.03)
    static let surface = Color(white: 0.14)
}

/// A pill with a thin outline, for the starter prompts. Phones and tablets get smaller pills,
/// so the starter prompts fit on one line.
struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Self.font)
            // Wrap inside the screen width instead of running past its edge.
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, Self.verticalPadding)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface.opacity(configuration.isPressed ? 0.8 : 0.45)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.1)))
    }

    private static var font: Font {
        #if os(macOS)
        return .callout
        #else
        return .subheadline
        #endif
    }

    private static var horizontalPadding: CGFloat {
        #if os(macOS)
        return 14
        #else
        return 12
        #endif
    }

    private static var verticalPadding: CGFloat {
        #if os(macOS)
        return 8
        #else
        return 6
        #endif
    }
}

/// A rounded panel with a small title, used to group settings and other lists.
struct Card<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
    }
}

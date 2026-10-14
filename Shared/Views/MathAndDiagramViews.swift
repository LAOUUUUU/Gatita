//
//  MathAndDiagramViews.swift
//  Gatita
//

import BeautifulMermaid
import LaTeXSwiftUI
import SwiftUI

/// Text with math in it, drawn with LaTeXSwiftUI (MathJax, off the main thread). The plain text shows until the
/// math is ready, and math that does not parse stays as written. See `MathDetection` for what counts as math.
struct MathText: View {
    let text: String

    var body: some View {
        // Prices next to math ("$5 and $10") would otherwise be read as math themselves.
        LaTeX(MathDetection.escapingStrayDollars(text))
            .parsingMode(.onlyEquations)
            .blockMode(.blockViews)
            .renderingStyle(.original)
            .imageRenderingMode(.template)
            .errorMode(.original)
    }
}

/// A `math` or `latex` code block as one centred equation.
struct MathBlockView: View {
    let code: String

    var body: some View {
        MathText(text: RichCode.displayMath(code))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
    }
}

/// Draws Mermaid diagrams with the BeautifulMermaid package, natively and in Gatita's colors.
enum MermaidPicture {
    static let theme = DiagramTheme(background: BMColor(hex: "#1C1C1E"), foreground: BMColor(hex: "#F2F2F2"),
                                    accent: BMColor(hex: "#F56B24"), transparent: true)

    /// The diagram as a picture, or nil when it is a kind the package does not draw or does not parse.
    static func render(_ code: String) async -> BMImage? {
        try? await MermaidRenderer.renderImageAsync(source: code, theme: theme)
    }
}

/// A `mermaid` code block as a diagram. While a reply is still writing it, it waits for the code to settle before
/// drawing; a diagram it cannot draw shows as the code block.
struct MermaidBlockView: View {
    let code: String
    @State private var picture: BMImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let picture {
                image(picture)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: picture.size.width, maxHeight: 560)
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.03)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.1)))
            } else if failed {
                CodeBlockView(language: "mermaid", code: code)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
        }
        .task(id: code) {
            // A new piece of the reply cancels this wait, so a diagram is drawn once it stops changing.
            guard (try? await Task.sleep(for: .milliseconds(350))) != nil else { return }
            let drawn = await MermaidPicture.render(code)
            guard !Task.isCancelled else { return }
            picture = drawn
            failed = drawn == nil
        }
    }

    private func image(_ picture: BMImage) -> Image {
        #if os(macOS)
        Image(nsImage: picture)
        #else
        Image(uiImage: picture)
        #endif
    }
}

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
nonisolated enum MermaidPicture {
    static let theme = DiagramTheme(background: BMColor(hex: "#1C1C1E"), foreground: BMColor(hex: "#F2F2F2"),
                                    accent: BMColor(hex: "#F56B24"), transparent: true)
    static let scale: CGFloat = 2

    /// The diagram as a picture, or nil when it is a kind the package does not draw or does not parse. Laid out
    /// and drawn off the main thread.
    static func render(_ code: String) async -> BMImage? {
        let drawn = await Task.detached(priority: .userInitiated) { () -> (CGImage, CGSize)? in
            guard let prepared = try? MermaidImageRenderer(theme: theme).prepare(from: readableLabels(code)),
                  let image = picture(of: prepared) else { return nil }
            return (image, prepared.bounds.size)
        }.value
        guard let (image, size) = drawn else { return nil }
        #if os(macOS)
        return NSImage(cgImage: image, size: size)
        #else
        return UIImage(cgImage: image, scale: scale, orientation: .up)
        #endif
    }

    /// The label color for boxes the diagram fills with a light color.
    static let darkLabel = "#1C1C1E"
    private static let styleLine = try! NSRegularExpression(pattern: #"^(\s*(?:style|classDef)\s+\S+\s+)(.*?)(;?\s*)$"#)

    /// The diagram with dark labels on every box that a `style` or `classDef` line fills with a light color and
    /// gives no text color. Gatita's labels are near-white, so they vanished on the light boxes models like.
    static func readableLabels(_ code: String) -> String {
        code.components(separatedBy: "\n").map { line in
            let text = line as NSString
            guard let match = styleLine.firstMatch(in: line, range: NSRange(location: 0, length: text.length)) else { return line }
            let properties = text.substring(with: match.range(at: 2))
            let pairs = properties.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            guard !pairs.contains(where: { $0.hasPrefix("color:") }),
                  let fill = pairs.first(where: { $0.hasPrefix("fill:") }), isLight(String(fill.dropFirst(5))) else { return line }
            return text.substring(with: match.range(at: 1)) + properties + ",color:\(darkLabel)" + text.substring(with: match.range(at: 3))
        }.joined(separator: "\n")
    }

    /// Whether a #rgb or #rrggbb color is light.
    static func isLight(_ color: String) -> Bool {
        var digits = color.trimmingCharacters(in: .whitespaces)
        guard digits.hasPrefix("#") else { return false }
        digits.removeFirst()
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return false }
        let red = Double((value >> 16) & 0xFF) / 255, green = Double((value >> 8) & 0xFF) / 255, blue = Double(value & 0xFF) / 255
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue > 0.6
    }

    /// Draws a laid-out diagram on a canvas whose y axis points down, as the package's drawing expects. The
    /// package's own Mac picture uses a canvas whose y axis points up, so it came out upside down.
    static func picture(of prepared: PreparedDiagram) -> CGImage? {
        let bounds = prepared.bounds
        let width = Int((bounds.width * scale).rounded(.up)), height = Int((bounds.height * scale).rounded(.up))
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        #if canImport(UIKit)
        // On iPhone and iPad the package draws its labels with UIKit, into the current UIKit context.
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }
        #endif
        prepared.render(context, bounds)
        return context.makeImage()
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
        Image(platformImage: picture)
    }
}

/// An SVG code block as a picture, on white as a browser shows it, with a button to see its code. One that can't
/// be drawn (too long, broken, or reaching outside itself) shows as the code block, with its live preview.
struct SVGBlockView: View {
    let code: String
    @State private var picture: PlatformImage?
    @State private var failed = false
    @State private var showingCode = false

    var body: some View {
        Group {
            if failed {
                CodeBlockView(language: "svg", code: code)
                    .equatable()
            } else if showingCode {
                VStack(alignment: .leading, spacing: 6) {
                    CodeBlockView(language: "svg", code: code)
                        .equatable()
                    Button {
                        showingCode = false
                    } label: {
                        Label("Show picture", systemImage: "photo")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
            } else if let picture {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Text("SVG")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            showingCode = true
                        } label: {
                            Label("Code", systemImage: "chevron.left.forwardslash.chevron.right")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Show the SVG code")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.045))
                    Image(platformImage: picture)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: picture.size.width, maxHeight: 560)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(Color.white)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.1)))
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
        }
        .task(id: code) {
            // A new piece of the reply cancels this wait, so a picture is drawn once its code stops changing.
            guard (try? await Task.sleep(for: .milliseconds(350))) != nil else { return }
            let drawn = await SVGPicture.render(code)
            guard !Task.isCancelled else { return }
            picture = drawn
            failed = drawn == nil
        }
    }
}

extension Image {
    /// A picture drawn by Gatita: an NSImage on the Mac, a UIImage elsewhere.
    init(platformImage: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}

//
//  MathAndDiagramTests.swift
//  GatitaTests
//

import LaTeXSwiftUI
import XCTest
@testable import Gatita

/// Which text is drawn as math (LaTeX) and which code blocks as diagrams (Mermaid).
final class MathAndDiagramTests: XCTestCase {
    func testMathIsFoundInItsUsualForms() {
        XCTAssertTrue(MathDetection.containsMath("The area is $\\pi r^2$."))
        XCTAssertTrue(MathDetection.containsMath("Let $x$ be a number."))
        XCTAssertTrue(MathDetection.containsMath("Inline \\(a + b\\) works."))
        XCTAssertTrue(MathDetection.containsMath("$$\n\\int_0^1 x\\,dx\n$$"))
        XCTAssertTrue(MathDetection.containsMath("\\[ E = mc^2 \\]"))
    }

    func testPricesAndCodeAreNotMath() {
        XCTAssertFalse(MathDetection.containsMath("It costs $5 and $10 at the shop."))
        XCTAssertFalse(MathDetection.containsMath("Prices: $5, $10."))
        XCTAssertFalse(MathDetection.containsMath("Use `$x$` in your template."))
        XCTAssertFalse(MathDetection.containsMath("A lone $ sign."))
        XCTAssertFalse(MathDetection.containsMath("Shell: echo $HOME and $PATH"))
        XCTAssertFalse(MathDetection.containsMath("No math here."))
    }

    func testPricesNextToMathStayText() {
        XCTAssertEqual(MathDetection.escapingStrayDollars("Area $\\pi r^2$. A coffee costs $5 and a cake $10."),
                       "Area $\\pi r^2$. A coffee costs \\$5 and a cake \\$10.")
        XCTAssertEqual(MathDetection.escapingStrayDollars("$$x^2$$ costs $3"), "$$x^2$$ costs \\$3")
        XCTAssertEqual(MathDetection.escapingStrayDollars("\\(a\\) and $4"), "\\(a\\) and \\$4")
        XCTAssertEqual(MathDetection.escapingStrayDollars("Let $x$ be \\$2"), "Let $x$ be \\$2", "an escaped dollar stays as it is")
    }

    func testFencesPickTheirKind() {
        XCTAssertEqual(RichCode.kind(language: "mermaid"), .diagram)
        XCTAssertEqual(RichCode.kind(language: "Mermaid"), .diagram)
        XCTAssertEqual(RichCode.kind(language: "math"), .math)
        XCTAssertEqual(RichCode.kind(language: "latex"), .math)
        XCTAssertEqual(RichCode.kind(language: "tex"), .math)
        XCTAssertEqual(RichCode.kind(language: "swift"), .code)
        XCTAssertEqual(RichCode.kind(language: ""), .code)
    }

    func testDisplayMathIsWrappedOnce() {
        XCTAssertEqual(RichCode.displayMath("E = mc^2"), "$$E = mc^2$$")
        XCTAssertEqual(RichCode.displayMath("  $$x$$ "), "$$x$$", "already wrapped stays as it is")
    }

    // MARK: - Drawing math (with LaTeXSwiftUI, patched in Packages/LaTeXSwiftUI)

    func testNumbersBeforeABraceStillParse() throws {
        // MathJaxSwift's default number pattern had lost its backslashes, so "1}" was read as one number and
        // x_{n=1} failed with "Extra open brace". A failed formula comes back as a much wider picture of the error.
        for (digit, letter) in [(#"$$x_{n=1}$$"#, #"$$x_{n=a}$$"#), (#"$$\lim_{x \to 0} x$$"#, #"$$\lim_{x \to a} x$$"#),
                                (#"$$\sum_{n=1}^{\infty} \frac{1}{n^s}$$"#, #"$$\sum_{n=a}^{\infty} \frac{1}{n^s}$$"#)] {
            let withDigit = try XCTUnwrap(LaTeX.renderToImages(digit, xHeight: 8).first, digit)
            let withLetter = try XCTUnwrap(LaTeX.renderToImages(letter, xHeight: 8).first, letter)
            XCTAssertEqual(withDigit.size.width, withLetter.size.width, accuracy: withLetter.size.width * 0.25, digit)
        }
    }

    // MARK: - Drawing diagrams (with the BeautifulMermaid package)

    func testAFlowchartBecomesAPicture() async {
        let picture = await MermaidPicture.render("graph TD\n    A[Start] --> B{Done?}\n    B -->|Yes| C[End]")
        XCTAssertNotNil(picture)
    }

    func testDiagramsAreDrawnRightSideUp() async throws {
        // The top box is red, so a picture the right way up has its red in the top half. The package's own Mac
        // drawing came out upside down.
        let picture = await MermaidPicture.render("graph TD\n    A[Top] --> B[Bottom]\n    style A fill:#ff0000")
        let rows = try XCTUnwrap(PixelRows(picture), "the diagram was not drawn")
        let red = rows.rowsWhere { red, green, blue, alpha in alpha > 200 && red > 200 && green < 60 && blue < 60 }
        XCTAssertFalse(red.isEmpty, "no red box in the picture")
        XCTAssertLessThan(Double(red.reduce(0, +)) / Double(red.count), Double(rows.height) / 2, "the red top box is in the bottom half")
    }

    func testDiagramLabelsAreDrawn() async throws {
        // Labels are near-white (#F2F2F2) on dark boxes, so a labeled box has many bright pixels and an empty one
        // almost none. On the iPad the labels once went missing; that path is checked on the simulator, since
        // these tests run on the Mac.
        let labeled = await MermaidPicture.render("graph TD\n    A[Hello world from Gatita]")
        let empty = await MermaidPicture.render("graph TD\n    A[ ]")
        let bright: (UInt8, UInt8, UInt8, UInt8) -> Bool = { red, green, blue, alpha in alpha > 200 && red > 200 && green > 200 && blue > 200 }
        let withLabel = try XCTUnwrap(PixelRows(labeled)).rowsWhere(bright).count
        let withoutLabel = try XCTUnwrap(PixelRows(empty)).rowsWhere(bright).count
        XCTAssertGreaterThan(withLabel, withoutLabel + 100, "the label was not drawn")
    }

    func testLabelsOnLightBoxesAreDark() {
        let dark = MermaidPicture.darkLabel
        XCTAssertEqual(MermaidPicture.readableLabels("graph TD\n  A --> B\n  style A fill:#fde7ef"),
                       "graph TD\n  A --> B\n  style A fill:#fde7ef,color:\(dark)")
        XCTAssertEqual(MermaidPicture.readableLabels("    style A,B fill:#FFF,stroke:#333;"), "    style A,B fill:#FFF,stroke:#333,color:\(dark);")
        XCTAssertEqual(MermaidPicture.readableLabels("classDef done fill:#e3f3ff"), "classDef done fill:#e3f3ff,color:\(dark)")
        for unchanged in ["style A fill:#1a1a1a", "style A fill:#ffffff,color:#ff0000", "style A stroke:#fff",
                          "A[fill:#fff]", "style A fill:white"] {
            XCTAssertEqual(MermaidPicture.readableLabels(unchanged), unchanged)
        }
    }

    func testADiagramItCannotDrawStaysCode() async {
        let picture = await MermaidPicture.render("gantt\n    title Plan\n    section A\n    Task :a1, 2026-01-01, 3d")
        XCTAssertNil(picture, "a gantt chart is not one of the six kinds it draws, so the code block shows")
    }
}

/// The rows of a picture's pixels, top first, for checking which way up it was drawn.
struct PixelRows {
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    init?(_ picture: PlatformImage?) {
        #if os(macOS)
        guard let picture, let image = picture.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        #else
        guard let image = picture?.cgImage else { return nil }
        #endif
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    /// The row (from the top) of every pixel that matches.
    func rowsWhere(_ matches: (UInt8, UInt8, UInt8, UInt8) -> Bool) -> [Int] {
        var rows: [Int] = []
        for row in 0..<height {
            for column in 0..<width {
                let at = (row * width + column) * 4
                if matches(bytes[at], bytes[at + 1], bytes[at + 2], bytes[at + 3]) { rows.append(row) }
            }
        }
        return rows
    }
}

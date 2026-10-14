//
//  MathAndDiagramTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita
#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif

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

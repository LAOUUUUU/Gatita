//
//  MathAndDiagramTests.swift
//  GatitaTests
//

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

    // MARK: - Drawing diagrams (with the BeautifulMermaid package)

    func testAFlowchartBecomesAPicture() async {
        let picture = await MermaidPicture.render("graph TD\n    A[Start] --> B{Done?}\n    B -->|Yes| C[End]")
        XCTAssertNotNil(picture)
    }

    func testADiagramItCannotDrawStaysCode() async {
        let picture = await MermaidPicture.render("gantt\n    title Plan\n    section A\n    Task :a1, 2026-01-01, 3d")
        XCTAssertNil(picture, "a gantt chart is not one of the six kinds it draws, so the code block shows")
    }
}

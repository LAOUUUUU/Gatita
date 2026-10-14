//
//  SVGPictureTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// SVG code blocks drawn as pictures in the chat, with SwiftDraw.
final class SVGPictureTests: XCTestCase {
    private let redOnTop = ##"<svg xmlns="http://www.w3.org/2000/svg" width="120" height="80" viewBox="0 0 120 80"><rect width="120" height="30" fill="#ff0000"/><circle cx="60" cy="60" r="12" fill="#0000ff"/></svg>"##

    func testSVGBlocksArePictures() {
        XCTAssertEqual(RichCode.kind(language: "svg", code: redOnTop), .picture)
        XCTAssertEqual(RichCode.kind(language: "SVG", code: "  \n" + redOnTop), .picture)
        XCTAssertEqual(RichCode.kind(language: "xml", code: "<?xml version=\"1.0\"?>\n" + redOnTop), .picture)
        XCTAssertEqual(RichCode.kind(language: "", code: redOnTop), .picture)
        XCTAssertEqual(RichCode.kind(language: "html", code: redOnTop), .code, "HTML keeps its live preview")
        XCTAssertEqual(RichCode.kind(language: "xml", code: "<note>hi</note>"), .code)
        XCTAssertEqual(RichCode.kind(language: "mermaid", code: "graph TD"), .diagram)
    }

    func testAnSVGIsDrawnRightSideUp() async throws {
        let picture = await SVGPicture.render(redOnTop)
        let rows = try XCTUnwrap(PixelRows(picture), "the SVG was not drawn")
        let red = rows.rowsWhere { red, green, blue, alpha in alpha > 200 && red > 200 && green < 60 && blue < 60 }
        let blue = rows.rowsWhere { red, green, blue, alpha in alpha > 200 && blue > 200 && red < 60 && green < 60 }
        XCTAssertFalse(red.isEmpty)
        XCTAssertFalse(blue.isEmpty)
        XCTAssertLessThan(red.max() ?? .max, blue.min() ?? 0, "the red band belongs above the blue circle")
    }

    func testSVGsThatReachOutsideStayCode() async {
        for unsafe in [
            #"<svg xmlns="http://www.w3.org/2000/svg"><image href="https://example.com/a.png" width="10" height="10"/></svg>"#,
            #"<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"><image xlink:href="//example.com/a.png"/></svg>"#,
            #"<svg xmlns="http://www.w3.org/2000/svg"><image href="file:///etc/hosts"/></svg>"#,
            #"<svg xmlns="http://www.w3.org/2000/svg"><rect style="fill: url(https://example.com/p.svg#g)"/></svg>"#,
            #"<svg xmlns="http://www.w3.org/2000/svg"><style>@import url(x.css);</style></svg>"#,
            #"<!DOCTYPE svg [<!ENTITY hosts SYSTEM "/etc/hosts">]><svg xmlns="http://www.w3.org/2000/svg"><text>&hosts;</text></svg>"#,
        ] {
            XCTAssertFalse(SVGPicture.isSelfContained(unsafe), unsafe)
            let picture = await SVGPicture.render(unsafe)
            XCTAssertNil(picture, unsafe)
        }
        XCTAssertTrue(SVGPicture.isSelfContained(redOnTop), "the xmlns address is a name, not a link")
        XCTAssertTrue(SVGPicture.isSelfContained(#"<svg xmlns="http://www.w3.org/2000/svg"><rect fill="url(#grad)"/></svg>"#))
    }

    func testAHugeSVGIsDrawnSmaller() async throws {
        let huge = ##"<svg xmlns="http://www.w3.org/2000/svg" width="100000" height="50000"><rect width="100000" height="50000" fill="#ff0000"/></svg>"##
        let picture = await SVGPicture.render(huge)
        let rows = try XCTUnwrap(PixelRows(picture))
        XCTAssertLessThanOrEqual(max(rows.width, rows.height), Int(SVGPicture.maxSide * SVGPicture.scale))
        XCTAssertEqual(Double(rows.width) / Double(rows.height), 2, accuracy: 0.05, "keeps its shape")
    }

    func testSomethingThatIsNotAnSVGIsNotDrawn() async {
        let notSVG = await SVGPicture.render("<html><body>hi</body></html>")
        XCTAssertNil(notSVG)
        let tooBig = await SVGPicture.render("<svg>" + String(repeating: " ", count: SVGPicture.maxCharacters) + "</svg>")
        XCTAssertNil(tooBig)
    }

    func testTheModelIsToldWhatGatitaDraws() {
        let text = ReplyFormat.instructions
        for word in ["```mermaid", "```svg", "$$"] {
            XCTAssertTrue(text.contains(word), word)
        }
    }
}

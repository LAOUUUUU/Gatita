//
//  ChartTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// Charts: a chart block in a reply is drawn; a block that is not valid chart data stays as code.
final class ChartTests: XCTestCase {
    private let bar = #"{"type":"bar","title":"Sales","points":[{"label":"Jan","value":12},{"label":"Feb","value":7.5}]}"#

    func testAValidChartParses() {
        let spec = ChartSpec.parse(bar)
        XCTAssertEqual(spec?.type, "bar")
        XCTAssertEqual(spec?.points.count, 2)
        XCTAssertEqual(spec?.points.last?.value, 7.5)
    }

    func testAnUnknownKindIsRefused() {
        XCTAssertNil(ChartSpec.parse(#"{"type":"radar","points":[{"label":"a","value":1}]}"#))
    }

    func testNoPointsIsRefused() {
        XCTAssertNil(ChartSpec.parse(#"{"type":"bar","points":[]}"#))
    }

    func testTooManyPointsIsRefused() {
        let points = (1...51).map { #"{"label":"\#($0)","value":1}"# }.joined(separator: ",")
        XCTAssertNil(ChartSpec.parse(#"{"type":"line","points":[\#(points)]}"#))
    }

    func testAValueThatIsNotANumberIsRefused() {
        XCTAssertNil(ChartSpec.parse(#"{"type":"bar","points":[{"label":"a","value":"ten"}]}"#))
    }

    func testAChartBlockBecomesAChartAndBadDataStaysCode() {
        XCTAssertEqual(MarkdownBlocks.parse("```chart\n\(bar)\n```"), [.chart(ChartSpec.parse(bar)!)])
        XCTAssertEqual(MarkdownBlocks.parse("```chart\nnot json\n```"),
                       [.code(language: "chart", text: "not json")])
    }

    func testTheChartsSkillTeachesTheBlock() {
        let instructions = Skills.instructions(for: "charts") ?? ""
        XCTAssertTrue(instructions.contains("```chart"), instructions)
        XCTAssertTrue(instructions.contains("points"), instructions)
    }
}

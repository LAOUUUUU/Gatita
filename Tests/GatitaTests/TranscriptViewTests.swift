//
//  TranscriptViewTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// The transcript views: Normal shows only the text, Thinking adds thinking and tool calls minimized,
/// and Verbose shows everything open.
final class TranscriptViewTests: XCTestCase {
    func testNormalShowsOnlyTheText() {
        XCTAssertFalse(TranscriptView.normal.showsThinking)
        XCTAssertFalse(TranscriptView.normal.showsToolCalls)
    }

    func testThinkingShowsToolCallsAndThinkingMinimized() {
        XCTAssertTrue(TranscriptView.thinking.showsThinking)
        XCTAssertTrue(TranscriptView.thinking.showsToolCalls)
        XCTAssertFalse(TranscriptView.thinking.expandsThinking)
        XCTAssertFalse(TranscriptView.thinking.expandsToolCalls)
    }

    func testVerboseShowsEverythingOpen() {
        XCTAssertTrue(TranscriptView.verbose.showsThinking)
        XCTAssertTrue(TranscriptView.verbose.showsToolCalls)
        XCTAssertTrue(TranscriptView.verbose.expandsThinking)
        XCTAssertTrue(TranscriptView.verbose.expandsToolCalls)
    }

    func testNormalIsTheDefaultAndTheChoiceIsSaved() throws {
        XCTAssertEqual(AppSettings().transcriptView, .normal)
        var settings = AppSettings()
        settings.transcriptView = .verbose
        let loaded = try JSONDecoder().decode(AppSettings.self, from: try JSONEncoder().encode(settings))
        XCTAssertEqual(loaded.transcriptView, .verbose)
    }

    func testTheMenuHasThreeNamedChoices() {
        XCTAssertEqual(TranscriptView.allCases.map(\.title), ["Normal", "Thinking", "Verbose"])
    }
}

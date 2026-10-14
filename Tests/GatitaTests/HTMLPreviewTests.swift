//
//  HTMLPreviewTests.swift
//  GatitaTests
//

import WebKit
import XCTest
@testable import Gatita

/// The live preview of HTML and SVG code blocks, which never reaches the network.
final class HTMLPreviewTests: XCTestCase {
    func testHTMLAndSVGBlocksCanBePreviewed() {
        XCTAssertTrue(HTMLPreview.canPreview(language: "html", code: "<p>hi</p>"))
        XCTAssertTrue(HTMLPreview.canPreview(language: "HTM", code: "<p>hi</p>"))
        XCTAssertTrue(HTMLPreview.canPreview(language: "svg", code: "<svg></svg>"))
        XCTAssertTrue(HTMLPreview.canPreview(language: "xml", code: "  <svg viewBox=\"0 0 1 1\"></svg>"))
        XCTAssertTrue(HTMLPreview.canPreview(language: "", code: "<!DOCTYPE html>\n<html></html>"))
        XCTAssertFalse(HTMLPreview.canPreview(language: "xml", code: "<plist></plist>"))
        XCTAssertFalse(HTMLPreview.canPreview(language: "swift", code: "let html = \"<p>\""))
        XCTAssertFalse(HTMLPreview.canPreview(language: "", code: "just text"))
    }

    func testThePageGetsAPolicyThatAllowsNoNetwork() {
        let page = HTMLPreview.document(language: "html", code: "<html><head><title>T</title></head><body>x</body></html>")
        XCTAssertTrue(page.hasPrefix(HTMLPreview.policyTag), "first, before anything that could run")
        XCTAssertTrue(HTMLPreview.policyTag.contains("default-src 'none'"))
        let early = HTMLPreview.document(language: "html", code: "<!DOCTYPE html>\n<html><head lang=\"en\"><script>x()</script></head></html>")
        XCTAssertTrue(early.hasPrefix("<!DOCTYPE html>\n" + HTMLPreview.policyTag), "after the doctype, which must stay first")

        let bare = HTMLPreview.document(language: "html", code: "<p>Hello</p>")
        XCTAssertTrue(bare.hasPrefix(HTMLPreview.policyTag), bare)
        XCTAssertTrue(bare.contains("<p>Hello</p>"))
    }

    func testAnSVGIsShownInAPage() {
        let page = HTMLPreview.document(language: "svg", code: "<svg width=\"10\"></svg>")
        XCTAssertTrue(page.contains("<body>"), page)
        XCTAssertTrue(page.contains("<svg width=\"10\"></svg>"))
        XCTAssertTrue(page.contains(HTMLPreview.policyTag))
    }

    func testTheBlockRuleCoversEveryLoad() throws {
        let rules = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(HTMLPreview.blockRules.utf8)) as? [[String: Any]])
        let trigger = try XCTUnwrap(rules.first?["trigger"] as? [String: Any])
        let action = try XCTUnwrap(rules.first?["action"] as? [String: Any])
        XCTAssertEqual(trigger["url-filter"] as? String, ".*")
        XCTAssertEqual(action["type"] as? String, "block")
    }

    func testThePreviewNeverNavigatesAway() {
        XCTAssertTrue(HTMLPreview.allowsNavigation(to: nil))
        XCTAssertTrue(HTMLPreview.allowsNavigation(to: URL(string: "about:blank")))
        XCTAssertTrue(HTMLPreview.allowsNavigation(to: URL(string: "about:blank#section")))
        XCTAssertFalse(HTMLPreview.allowsNavigation(to: URL(string: "https://example.com")))
        XCTAssertFalse(HTMLPreview.allowsNavigation(to: URL(string: "file:///etc/passwd")))
    }
}

/// A real web view with the preview's settings: the page shows, and a picture from the internet does not load.
@MainActor
final class HTMLPreviewWebTests: XCTestCase {
    func testThePageShowsButCannotReachTheNetwork() async throws {
        let rules = await PreviewRules.list()
        XCTAssertNotNil(rules, "the block rule compiles")
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 400, height: 300),
                             configuration: PreviewWebView.configuration(rules: rules))
        let page = HTMLPreview.document(language: "html", code: """
            <html><head></head><body><p id="x">Hello</p>
            <img src="https://example.com/a.png" onload="document.title='loaded'" onerror="document.title='blocked'">
            </body></html>
            """)
        view.loadHTMLString(page, baseURL: nil)
        var title = ""
        for _ in 0..<80 where title.isEmpty {
            try await Task.sleep(nanoseconds: 100_000_000)
            title = view.title ?? ""
        }
        let text = try await view.evaluateJavaScript("document.getElementById('x').textContent") as? String
        XCTAssertEqual(text, "Hello", "the page itself loads")
        XCTAssertEqual(title, "blocked", "the picture from the internet does not")
    }
}

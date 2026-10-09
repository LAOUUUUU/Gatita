//
//  WebCheck.swift
//  Gatita
//

import Foundation

#if os(macOS)
import AppKit
import WebKit

/// Loads a local HTML page at a phone width and a desktop width and reports what it finds as text.
/// It measures instead of showing a picture: horizontal overflow, broken images, missing alt text,
/// small tap targets, script errors, headings, and the visible text.
@MainActor
enum WebCheck {
    static let widths: [CGFloat] = [390, 1280]

    static func check(file: URL, root: URL) async throws -> String {
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw ToolError("no such file: \(file.lastPathComponent)")
        }
        var sections: [String] = []
        for width in widths {
            let json = try await measure(file: file, root: root, width: width)
            sections.append("## \(Int(width))px wide\n" + format(json))
        }
        return sections.joined(separator: "\n\n")
    }

    private static func measure(file: URL, root: URL, width: CGFloat) async throws -> String {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(
            WKUserScript(source: errorProbe, injectionTime: .atDocumentStart, forMainFrameOnly: true))

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: 900), configuration: configuration)
        let window = NSWindow(contentRect: webView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = webView
        defer { window.close() }

        let loader = PageLoader()
        try await loader.load(webView, file: file, root: root)
        let result = try await webView.evaluateJavaScript(measureScript)
        return (result as? String) ?? "{}"
    }

    private static let errorProbe = """
    window.__gatitaErrors = [];
    window.addEventListener('error', function (event) { window.__gatitaErrors.push(String(event.message)); });
    """

    private static let measureScript = """
    (function () {
      var issues = [];
      var overflow = document.documentElement.scrollWidth - window.innerWidth;
      if (overflow > 1) issues.push('page is ' + overflow + 'px wider than the window (horizontal scrolling)');
      var images = Array.prototype.slice.call(document.images);
      var broken = images.filter(function (img) { return img.complete && img.naturalWidth === 0; });
      if (broken.length) issues.push(broken.length + ' broken image(s): ' + broken.map(function (i) { return i.getAttribute('src'); }).join(', '));
      var noAlt = images.filter(function (img) { return !img.hasAttribute('alt'); }).length;
      if (noAlt) issues.push(noAlt + ' image(s) without alt text');
      var targets = Array.prototype.filter.call(document.querySelectorAll('a, button, input, select, textarea'), function (el) {
        var r = el.getBoundingClientRect();
        return r.width > 0 && (r.width < 24 || r.height < 24);
      }).length;
      if (targets) issues.push(targets + ' tap target(s) smaller than 24px');
      var headings = Array.prototype.map.call(document.querySelectorAll('h1, h2, h3'), function (h) {
        return h.tagName + ': ' + h.textContent.trim().slice(0, 80);
      });
      var text = document.body ? document.body.innerText.trim().slice(0, 800) : '';
      return JSON.stringify({
        title: document.title,
        issues: issues,
        errors: window.__gatitaErrors || [],
        headings: headings,
        text: text
      });
    })()
    """

    private struct Report: Decodable {
        let title: String
        let issues: [String]
        let errors: [String]
        let headings: [String]
        let text: String
    }

    private static func format(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let report = try? JSONDecoder().decode(Report.self, from: data) else {
            return "could not read the page measurements"
        }
        var lines = ["Title: \(report.title.isEmpty ? "(none)" : report.title)"]
        lines.append(report.issues.isEmpty
                     ? "Layout: no problems found"
                     : "Problems:\n" + report.issues.map { "- \($0)" }.joined(separator: "\n"))
        if !report.errors.isEmpty {
            lines.append("Script errors:\n" + report.errors.map { "- \($0)" }.joined(separator: "\n"))
        }
        if !report.headings.isEmpty {
            lines.append("Headings:\n" + report.headings.map { "- \($0)" }.joined(separator: "\n"))
        }
        lines.append("Visible text (start):\n" + report.text)
        return lines.joined(separator: "\n")
    }
}

/// Waits for one page load to finish, or fail, or time out.
@MainActor
private final class PageLoader: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func load(_ webView: WKWebView, file: URL, root: URL) async throws {
        webView.navigationDelegate = self
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            webView.loadFileURL(file, allowingReadAccessTo: root)
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
                self?.finish(.failure(ToolError("the page did not finish loading")))
            }
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(.success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }
}
#endif

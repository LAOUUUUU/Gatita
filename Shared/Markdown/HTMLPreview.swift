//
//  HTMLPreview.swift
//  Gatita
//

import Foundation

/// What the live preview of an HTML or SVG code block shows, and the rules that keep it off the network: a
/// Content-Security-Policy tag in the page, a content rule that blocks every load, and no navigation away.
/// Scripts run, since many previews need them, but nothing can reach Gatita or the internet.
nonisolated enum HTMLPreview {
    /// Allows only what is inside the page itself.
    static let policyTag = #"<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src data: blob:; font-src data:; media-src data: blob:">"#

    /// A WebKit content rule list that blocks every load.
    static let blockRules = #"[{"trigger": {"url-filter": ".*"}, "action": {"type": "block"}}]"#

    private static let htmlLanguages: Set<String> = ["html", "htm", "xhtml"]

    /// Whether a code block is a page or a picture the preview can show.
    static func canPreview(language: String, code: String) -> Bool {
        let language = language.lowercased()
        let start = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if htmlLanguages.contains(language) || language == "svg" { return true }
        if language == "xml" { return start.hasPrefix("<svg") }
        if language.isEmpty { return start.hasPrefix("<!doctype html") || start.hasPrefix("<html") || start.hasPrefix("<svg") }
        return false
    }

    /// The page to load: the HTML with the policy at the top of its head, or an SVG centred in a page.
    static func document(language: String, code: String) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if language.lowercased() == "svg" || (!htmlLanguages.contains(language.lowercased()) && trimmed.lowercased().hasPrefix("<svg")) {
            return """
                <!DOCTYPE html><html><head>\(policyTag)<meta name="viewport" content="width=device-width, initial-scale=1">\
                <style>html, body { margin: 0; height: 100%; } body { display: flex; align-items: center; \
                justify-content: center; background: #fff; } svg { max-width: 100%; max-height: 100%; }</style>\
                </head><body>\(trimmed)</body></html>
                """
        }
        // The policy goes first, before anything that could run. Only a doctype may come before it, since it must
        // stay the first thing in the page; the browser moves the tag into the page's head itself.
        if let doctype = code.range(of: #"^\s*<!doctype[^>]*>\s*"#, options: [.regularExpression, .caseInsensitive]) {
            return code[..<doctype.upperBound] + policyTag + code[doctype.upperBound...]
        }
        return policyTag + code
    }

    /// Whether the preview may go to an address: only the page itself, never anywhere else.
    static func allowsNavigation(to url: URL?) -> Bool {
        guard let url else { return true }
        return url.scheme == "about" && url.absoluteString.hasPrefix("about:blank")
    }
}

//
//  WebFetch.swift
//  Gatita
//

import Foundation

/// Reads the text of a public web page for the web connector.
nonisolated enum WebFetch {
    /// A page this connector may read: https, on a public host. Local and private addresses are refused.
    static func validate(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespaces)),
              url.scheme == "https", let host = url.host?.lowercased(), !host.isEmpty else { return nil }

        if host == "localhost" || host.hasSuffix(".local") || host.hasPrefix("[") { return nil }
        let privatePrefixes = ["127.", "10.", "192.168.", "169.254.", "0."]
        if privatePrefixes.contains(where: { host.hasPrefix($0) }) { return nil }

        let octets = host.split(separator: ".")
        if octets.count == 4, octets[0] == "172", let second = Int(octets[1]), (16...31).contains(second) {
            return nil
        }
        return url
    }

    /// Visible text from HTML: scripts and styles dropped, tags removed, common entities decoded.
    static func plainText(from html: String) -> String {
        var text = replace(html, pattern: "(?is)<(script|style)[^>]*>.*?</\\1>", with: " ")
        text = replace(text, pattern: "(?s)<[^>]+>", with: " ")
        let entities = [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")]
        for (entity, character) in entities {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        return text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func fetch(_ address: String) async throws -> String {
        guard let url = validate(address) else {
            throw ToolError("only public https addresses can be read")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("text/html, text/plain", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ToolError("the page did not load")
        }
        // URLSession follows redirects, so check where the page actually came from.
        guard let redirected = http.url, validate(redirected.absoluteString) != nil else {
            throw ToolError("the page redirected to an address that cannot be read")
        }

        let html = String(decoding: data.prefix(2_000_000), as: UTF8.self)
        return String(plainText(from: html).prefix(20_000))
    }

    private static func replace(_ text: String, pattern: String, with replacement: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
        return expression.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text),
                                                   withTemplate: replacement)
    }
}

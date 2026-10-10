//
//  WebCurl.swift
//  Gatita
//

import Foundation

/// A raw GET request for the web connector, like `curl -i`: the status, the main headers, and the body as text.
/// Use it for APIs, JSON, and redirects. Reading a page as text is WebFetch.
nonisolated enum WebCurl {
    static let maxCharacters = 20_000
    private static let maxBytes = 2_000_000
    private static let shownHeaders = ["content-type", "content-length", "last-modified", "location"]

    /// Sends a GET to a public https address and renders the answer. Redirects are followed, and the
    /// address they land on must also be public.
    static func fetch(_ address: String) async throws -> String {
        guard let url = WebFetch.validate(address) else {
            throw ToolError("only public https addresses can be read")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("*/*", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ToolError("no response from the address")
        }
        guard let final = http.url, WebFetch.validate(final.absoluteString) != nil else {
            throw ToolError("the address redirected to one that cannot be read")
        }

        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let key = key as? String, let value = value as? String {
                headers[key] = value
            }
        }
        return try render(status: http.statusCode, url: final.absoluteString,
                          headers: headers, body: Data(data.prefix(maxBytes)))
    }

    /// The text the model sees: a status line, the headers that matter, a blank line, then the body.
    /// Bodies that are not text (images, archives, and so on) are refused rather than printed.
    static func render(status: Int, url: String, headers: [String: String], body: Data) throws -> String {
        let lower = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
        var lines = ["HTTP \(status) \(url)"]
        for name in shownHeaders {
            if let value = lower[name] {
                lines.append("\(name): \(value)")
            }
        }

        let decoded: String
        if let type = lower["content-type"] {
            guard isText(type) else {
                throw ToolError("the response is \(type), which is not shown as text")
            }
            decoded = String(decoding: body, as: UTF8.self)
        } else {
            guard let strict = String(data: body, encoding: .utf8) else {
                throw ToolError("the response has no type and is not text")
            }
            decoded = strict
        }

        let capped = String(decoded.prefix(maxCharacters))
        let cut = decoded.count > maxCharacters ? "\n[cut at 20,000 characters]" : ""
        return (lines + ["", capped + cut]).joined(separator: "\n")
    }

    /// Text types, plus the structured formats that are text in practice (JSON, XML, and so on).
    static func isText(_ contentType: String) -> Bool {
        let type = contentType.lowercased()
        return type.hasPrefix("text/")
            || ["json", "xml", "javascript", "yaml", "x-www-form-urlencoded"].contains { type.contains($0) }
    }
}

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
        guard let http = response as? HTTPURLResponse else { throw ToolError("the page did not load") }
        guard (200..<300).contains(http.statusCode) else { throw ToolError(statusError(http.statusCode)) }
        // URLSession follows redirects, so check where the page actually came from.
        guard let redirected = http.url, validate(redirected.absoluteString) != nil else {
            throw ToolError("the page redirected to an address that cannot be read")
        }

        let html = String(decoding: data.prefix(2_000_000), as: UTF8.self)
        return String(plainText(from: html).prefix(20_000))
    }

    /// Why a page did not load, with its status, so the model stops guessing at addresses that do not exist.
    static func statusError(_ status: Int) -> String {
        status == 404
            ? "the page answered HTTP 404: it does not exist. Do not guess addresses; find the right one in a page that links to it, or ask the user."
            : "the page answered HTTP \(status)"
    }

    /// The most pages one web_fetch call reads.
    static let maxPages = 5

    /// The addresses a call asks for: "urls" (one per line, or separated by commas), or else "url". Blanks and
    /// repeats are dropped. A line is split at its commas only when every piece is an address, since an address
    /// can hold a comma itself (Washington,_D.C. or ?ids=1,2).
    static func addresses(_ arguments: [String: String]) -> [String] {
        let text = arguments["urls"] ?? arguments["url"] ?? ""
        var seen = Set<String>()
        return text.components(separatedBy: "\n").flatMap { line -> [String] in
            let pieces = line.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let several = pieces.count > 1 && pieces.allSatisfy { $0.hasPrefix("https://") || $0.hasPrefix("http://") }
            return several ? pieces : [line.trimmingCharacters(in: .whitespaces)]
        }
        .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Reads up to five pages at the same time and returns them as one text, each between start and end lines.
    static func fetchMany(_ addresses: [String]) async throws -> String {
        guard addresses.count <= maxPages else {
            throw ToolError("\(addresses.count) pages is too many. Read at most \(maxPages) at a time.")
        }
        let results = await withTaskGroup(of: (Int, Result<String, Error>).self) { group in
            for (index, address) in addresses.enumerated() {
                group.addTask {
                    do { return (index, .success(try await fetch(address))) } catch { return (index, .failure(error)) }
                }
            }
            var collected: [(Int, Result<String, Error>)] = []
            for await result in group { collected.append(result) }
            return collected.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
        return combine(Array(zip(addresses, results)))
    }

    static func combine(_ pages: [(String, Result<String, Error>)]) -> String {
        var read = 0
        let parts = pages.map { address, result -> String in
            let body: String
            switch result {
            case .success(let text):
                read += 1
                body = text
            case .failure(let error):
                body = NoInternet.matches(error, online: true)
                    ? "error: no internet access"
                    : "error: \(error.localizedDescription)"
            }
            return "===== start of \(address) =====\n\(body)\n===== end of \(address) ====="
        }
        return (["Read \(read) of \(pages.count) pages."] + parts).joined(separator: "\n\n")
    }

    private static func replace(_ text: String, pattern: String, with replacement: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
        return expression.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text),
                                                   withTemplate: replacement)
    }
}

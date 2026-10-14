//
//  PublicAPI.swift
//  Gatita
//

import Foundation

/// The shared side of the connectors that read free public services (weather, Wikipedia, packages, and so on):
/// one GET with Gatita's User-Agent, JSON reading, and text cleanup. No keys and no sign-in are used.
nonisolated enum PublicAPI {
    /// Wikimedia, crates.io, and GitHub ask every client to name itself and give a way to reach its maker.
    /// Read from the bundle here rather than from AppVersion, since connectors run off the main actor.
    static var userAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return "Gatita/\(version) (https://github.com/LAOUUUUU/Gatita)"
    }

    static let maxBytes = 2_000_000
    static let maxCharacters = 20_000

    /// One GET. The status comes back with the body, so each connector can explain a 404 in its own words.
    static func get(_ url: URL, accept: String = "application/json") async throws -> (data: Data, status: Int) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ToolError("no response from \(url.host ?? "the service")")
        }
        return (Data(data.prefix(maxBytes)), http.statusCode)
    }

    /// A GET whose answer must be 2xx. Other statuses become an error that names the service.
    static func getOK(_ url: URL, service: String, accept: String = "application/json",
                      notFound: String? = nil) async throws -> Data {
        let (data, status) = try await get(url, accept: accept)
        if status == 404, let notFound { throw ToolError(notFound) }
        guard (200..<300).contains(status) else {
            throw ToolError("\(service) answered HTTP \(status)\(reason(in: data).map { ": \($0)" } ?? "")")
        }
        return data
    }

    /// A short reason from a JSON error body, such as {"message": "..."}.
    static func reason(in data: Data) -> String? {
        guard let object = object(data) else { return nil }
        for key in ["message", "error_message", "error", "title"] {
            if let text = object[key] as? String, !text.isEmpty { return String(text.prefix(300)) }
        }
        return nil
    }

    static func object(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static func array(_ data: Data) -> [Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [Any]
    }

    /// A JSON object, or an error that says the service answered with something else.
    static func requireObject(_ data: Data, service: String) throws -> [String: Any] {
        guard let object = object(data) else { throw ToolError("\(service) sent an answer that could not be read") }
        return object
    }

    /// An https address built from parts. Throws when the parts do not make one.
    static func url(_ base: String, path: String = "", query: [(String, String)] = []) throws -> URL {
        guard var components = URLComponents(string: base + path) else { throw ToolError("could not build the address") }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        }
        guard let url = components.url, url.scheme == "https" else { throw ToolError("could not build the address") }
        return url
    }

    /// Text safe to put in one path segment: spaces and slashes are escaped, nothing else changes.
    static func pathSegment(_ text: String) -> String {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#;"))
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    /// HTML entities as their characters: the common names and numeric forms such as &#39; and &#x41;.
    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "hellip": "…",
                     "mdash": "—", "ndash": "–", "rsquo": "’", "lsquo": "‘", "rdquo": "”", "ldquo": "“"]
        guard let pattern = try? NSRegularExpression(pattern: "&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);") else { return text }
        var result = ""
        var last = text.startIndex
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let whole = Range(match.range, in: text), let body = Range(match.range(at: 1), in: text) else { continue }
            result += text[last..<whole.lowerBound]
            let name = String(text[body])
            var replacement: String?
            if name.hasPrefix("#x"), let value = UInt32(name.dropFirst(2), radix: 16), let scalar = Unicode.Scalar(value) {
                replacement = String(Character(scalar))
            } else if name.hasPrefix("#"), let value = UInt32(name.dropFirst()), let scalar = Unicode.Scalar(value) {
                replacement = String(Character(scalar))
            } else {
                replacement = named[name]
            }
            result += replacement ?? String(text[whole])
            last = whole.upperBound
        }
        result += text[last...]
        return result
    }

    /// Tags removed and entities decoded, for short HTML such as a search excerpt.
    static func stripTags(_ html: String) -> String {
        decodeEntities(replace(html, "(?s)<[^>]+>", with: ""))
    }

    static func replace(_ text: String, _ pattern: String, with template: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
        return expression.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    /// Text cut to `limit` characters, with the cut marked.
    static func capped(_ text: String, _ limit: Int = maxCharacters) -> String {
        text.count > limit ? String(text.prefix(limit)) + "\n[cut at \(limit) characters]" : text
    }

    /// "2026-10-10" from "2026-10-10T02:44:18Z". Text that is not a timestamp comes back as it was.
    static func day(_ timestamp: String) -> String {
        timestamp.count >= 10 ? String(timestamp.prefix(10)) : timestamp
    }

    /// A number as plain text: no grouping, a dot for decimals, and at most `digits` decimals.
    static func number(_ value: Double, digits: Int = 4) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = digits
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// A JSON value that should be a number, as a Double.
    static func double(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue ?? (value as? String).flatMap(Double.init)
    }
}

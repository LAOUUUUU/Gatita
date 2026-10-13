//
//  RateLimit.swift
//  Gatita
//

import Foundation

/// What to do with an HTTP 429 from the Gatita API: how long the server asked to wait, and the line the chat
/// shows while it waits. The API allows a few requests a minute, so a long run of tool calls can reach it.
nonisolated enum RateLimit {
    /// How many times one turn waits and sends again before the 429 becomes the reply's error.
    static let maxWaits = 2
    /// The wait when the server does not say how long.
    static let defaultWait: TimeInterval = 30
    /// The longest wait worth sitting through. A longer one, such as a daily limit, is shown as the error.
    static let longestWait: TimeInterval = 75

    /// Seconds to wait, from a Retry-After header in seconds, or a body field named retryAfter or retry_after,
    /// at the top or inside "error". Nil when neither says.
    static func delay(header: String?, body: String) -> TimeInterval? {
        if let header, let seconds = TimeInterval(header.trimmingCharacters(in: .whitespaces)) {
            return seconds
        }
        guard let object = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any] else { return nil }
        let places = [object, object["error"] as? [String: Any]].compactMap { $0 }
        for place in places {
            for key in ["retryAfter", "retry_after"] {
                if let number = place[key] as? NSNumber { return number.doubleValue }
                if let text = place[key] as? String, let seconds = TimeInterval(text) { return seconds }
            }
        }
        return nil
    }

    /// The wait to sit through, at least a second. Nil when the server asked for longer than `longestWait`.
    static func waitSeconds(_ delay: TimeInterval?) -> TimeInterval? {
        let seconds = delay ?? defaultWait
        guard seconds <= longestWait else { return nil }
        return max(1, seconds)
    }

    /// The line the chat shows while it waits, counting down to `until`.
    static func note(until: Date, now: Date = Date()) -> String {
        let left = Int(until.timeIntervalSince(now).rounded(.up))
        return left > 0
            ? "Gatita's rate limit was reached. Trying again in \(left) s."
            : "Gatita's rate limit was reached. Trying again now."
    }
}

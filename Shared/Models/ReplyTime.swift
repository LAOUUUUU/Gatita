//
//  ReplyTime.swift
//  Gatita
//

import Foundation

/// The time under a reply. Within a day it counts up ("5 min ago"). After a day it names the date and the time.
nonisolated enum ReplyTime {
    static func label(since date: Date, now: Date = Date(), timeZone: TimeZone = .current) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3_600 { return "\(Int(seconds / 60)) min ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600)) hr ago" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEEE, MMMM d 'at' h:mm a"
        return formatter.string(from: date)
    }
}

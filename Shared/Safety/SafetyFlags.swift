//
//  SafetyFlags.swift
//  Gatita
//

import Foundation

/// Local rules that refuse a message before it reaches Gatita. A message that matches one is never sent,
/// so these rules cost no tokens and answer at once. Keep them narrow: a rule that is too broad refuses ordinary questions.
nonisolated enum SafetyFlags {
    struct Flag: Equatable {
        let id: String
        /// What the user sees as the reason.
        let title: String
        /// Regular expressions, matched without regard to case.
        let patterns: [String]
    }

    static let all: [Flag] = [
        Flag(id: "explosives", title: "Making explosives, nerve agents, or biological or nuclear weapons",
             patterns: [#"\b(make|build|assemble|synthesi[sz]e|manufacture)\b.{0,30}\b(explosive device|pipe bomb|nail bomb|bomb-making|nerve agent|sarin|anthrax|bioweapon|nuclear weapon)\b"#]),
        Flag(id: "malware", title: "Writing malware",
             patterns: [#"\b(write|create|build|code)\b.{0,20}\b(ransomware|keylogger|computer virus|malware)\b"#]),
    ]

    /// The first rule the text matches, or nil.
    static func match(_ text: String) -> Flag? {
        all.first { flag in
            flag.patterns.contains { pattern in
                text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
            }
        }
    }
}

//
//  PairingCode.swift
//  Gatita
//

import Foundation

/// The code a Mac makes each time it opens pairing. A phone or iPad types it in to pair.
nonisolated enum PairingCode {
    /// Six digits, with leading zeros kept, from the system's random generator.
    static func make() -> String {
        let number = Int.random(in: 0..<1_000_000)
        let digits = String(number)
        return String(repeating: "0", count: 6 - digits.count) + digits
    }
}

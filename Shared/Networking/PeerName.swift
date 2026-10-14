//
//  PeerName.swift
//  Gatita
//

import Foundation

/// The name other devices see when pairing. MultipeerConnectivity throws an Objective-C exception for a name that
/// is empty or longer than 63 bytes of UTF-8, and a Mac's network host name can be either. The exception happens
/// while SwiftUI builds the app, and leaves its observation tracking pointing at freed memory.
nonisolated enum PeerName {
    static let maxBytes = 63

    /// The name trimmed, cut to 63 bytes between characters, or the fallback when nothing is left.
    static func safe(_ name: String?, fallback: String) -> String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        var result = ""
        for character in trimmed {
            guard result.utf8.count + character.utf8.count <= maxBytes else { break }
            result.append(character)
        }
        return result
    }
}

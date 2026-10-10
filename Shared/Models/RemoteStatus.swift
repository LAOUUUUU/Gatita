//
//  RemoteStatus.swift
//  Gatita
//

import Foundation

/// The lines that say whether a device is reaching the Mac, and whether a Mac has a device connected.
nonisolated enum RemoteStatus {
    /// On a phone or iPad: what the PC chat says about the connection.
    static func line(connectedName: String?) -> String {
        if let name = connectedName, !name.isEmpty {
            return "Connected to \(name). It's up. What would you like to do?"
        }
        return "Not connected to your Mac. Connect to it in Settings, then Pairing."
    }

    /// On a Mac: what the chat says while a device is connected. Nil when none is.
    static func hostLine(names: [String]) -> String? {
        guard let first = names.first else { return nil }
        return "\(first) is connected. It's up. What would you like to do?"
    }
}

//
//  RemoteMessage.swift
//  Gatita
//
//  Created by LAOUUU on 2026-10-08.
//

import Foundation

/// Messages between a client and a host. A host sends `chunk` pieces while Gatita writes, then one `response` with the whole reply.
enum RemoteMessage: Codable {
    case prompt(text: String, clientName: String)
    case chunk(text: String)
    case response(text: String)
    case status(String)
}

/// Builds the reply a client shows from what the host sends: pieces as they arrive, then the final response, which replaces them.
struct ReplyAssembler {
    private(set) var text = ""
    private(set) var isFinished = false

    mutating func receive(_ message: RemoteMessage) {
        guard !isFinished else { return }
        switch message {
        case .chunk(let piece):
            text += piece
        case .response(let finalText):
            text = finalText
            isFinished = true
        case .prompt, .status:
            break
        }
    }
}

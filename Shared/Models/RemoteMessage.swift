//
//  RemoteMessage.swift
//  Gatita
//
//  Created by LAOUUU on 2026-10-08.
//

import Foundation

enum RemoteMessage: Codable {
    case prompt(text: String, clientName: String)
    case response(text: String)
    case status(String)
}

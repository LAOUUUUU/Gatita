//
//  HostPolicy.swift
//  Gatita
//

import Foundation

/// What a host can do. The Mac is the full host: project files, edits, commands, GitHub, and pull requests.
/// iPhone, iPad, and Vision Pro are question-only hosts: they answer questions and read public web pages.
nonisolated enum HostPolicy {
    enum Kind: Sendable, Equatable {
        case mac
        case questionsOnly
    }

    /// The kind of host this build runs as.
    static var current: Kind {
        #if os(macOS)
        .mac
        #else
        .questionsOnly
        #endif
    }

    /// The project folder this host may use. Only the Mac has one, so a path saved on another host is ignored.
    static func projectRoot(_ path: String, on kind: Kind = current) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard kind == .mac, !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
    }

    /// Whether a connector can run on this host. GitHub reads need the Mac and its gh login.
    static func allows(_ connector: ConnectorInfo, on kind: Kind = current) -> Bool {
        kind == .mac || !connector.macOnly
    }

    /// The connectors from `enabled` that this host can run.
    static func connectors(_ enabled: Set<String>, on kind: Kind = current) -> Set<String> {
        Set(enabled.filter { id in
            Connectors.connector(named: id).map { allows($0, on: kind) } ?? false
        })
    }

    /// Whether a shop item can be used on this host. Connector items follow their connector.
    static func allows(_ item: ShopItem, on kind: Kind = current) -> Bool {
        guard let id = item.connectorID, let connector = Connectors.connector(named: id) else { return true }
        return allows(connector, on: kind)
    }
}

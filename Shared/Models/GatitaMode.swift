//
//  GatitaMode.swift
//  Gatita
//

import Foundation

/// How Gatita works in a chat.
/// Chat is regular chat: no project files, edits, commands, plugin commands, or GitHub.
/// Code works on a project: it reads and edits files (when turned on), runs allowed commands, uses plugins,
/// and reads GitHub, which needs a project folder.
nonisolated enum GatitaMode: String, Codable, CaseIterable, Sendable {
    case chat
    case code

    var displayName: String {
        switch self {
        case .chat: "Gatita Chat"
        case .code: "Gatita Code"
        }
    }

    var summary: String {
        switch self {
        case .chat: "Regular chat. No project files, edits, commands, plugin commands, or GitHub."
        case .code: "Reads and edits the project, runs allowed commands, and uses plugins. GitHub needs a project folder."
        }
    }

    /// Project files, edits, commands, and plugin commands are for Code only.
    var usesProjectTools: Bool { self == .code }

    /// The failure-report and question tools. Code has them, and so does every chat on a host with no project
    /// (iPhone and iPad), which is always in Chat. A Mac chat does not get them.
    var usesReportTools: Bool { self == .code || HostPolicy.current == .questionsOnly }

    /// Connectors that only read a project. They need Code mode and a project folder.
    private static let projectConnectors: Set<String> = ["github"]

    /// Whether a connector may run in this mode.
    func allows(connector id: String, hasProject: Bool) -> Bool {
        guard Self.projectConnectors.contains(id) else { return true }
        return self == .code && hasProject
    }

    /// The connectors from `enabled` that may run in this mode.
    func connectors(_ enabled: Set<String>, hasProject: Bool) -> Set<String> {
        enabled.filter { allows(connector: $0, hasProject: hasProject) }
    }
}

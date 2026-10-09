//
//  Shop.swift
//  Gatita
//

import Foundation

/// Plugins add commands and skills. Skills add one instruction set. Connectors are built in and only read outside services.
nonisolated enum ShopKind: Sendable {
    case plugin
    case skill
    case connector
}

/// The three tabs of the shop.
nonisolated enum ShopCategory: String, CaseIterable, Identifiable, Sendable {
    case plugins
    case connectors
    case skills

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plugins: return "Plugins"
        case .connectors: return "Connectors"
        case .skills: return "Skills"
        }
    }

    var kind: ShopKind {
        switch self {
        case .plugins: return .plugin
        case .connectors: return .connector
        case .skills: return .skill
        }
    }

    var intro: String {
        switch self {
        case .plugins: return "Plugins add commands and skills. Commands run sandboxed, with no network, when you turn on running commands in Settings."
        case .connectors: return "Connectors read outside services. Turning one on keeps it on for this chat, and mentioning !name uses it for one message."
        case .skills: return "Skills are instructions Gatita follows. Pick one with / in the input, or from the skill menu."
        }
    }
}

nonisolated struct ShopItem: Identifiable, Sendable {
    let id: String
    let name: String
    let kind: ShopKind
    let summary: String
    /// For plugins and skills: the contents of plugin.json. Empty for connectors.
    let manifest: String
    /// For connectors: the id used by the connector list and the "!" menu.
    let connectorID: String?
}

/// The free items on offer. Everything here is bundled with the app; nothing is downloaded or run to install it.
nonisolated enum Shop {
    static let items: [ShopItem] = [
        ShopItem(id: "swift-dev", name: "Swift developer", kind: .plugin,
                 summary: "A SwiftUI review skill, and a command that lists the Xcode project's schemes.",
                 manifest: swiftDeveloper, connectorID: nil),
        ShopItem(id: "release-notes", name: "Release notes", kind: .plugin,
                 summary: "Drafts release notes from the latest tag and the commits since it.",
                 manifest: releaseNotes, connectorID: nil),
        ShopItem(id: "node-tools", name: "Node tools", kind: .plugin,
                 summary: "Runs the project's lint script, and a skill that fixes what it reports.",
                 manifest: nodeTools, connectorID: nil),

        ShopItem(id: "github-connector", name: "GitHub", kind: .connector,
                 summary: "Reads pull requests, checks, and issues through your gh login. Read-only.",
                 manifest: "", connectorID: "github"),
        ShopItem(id: "web-connector", name: "Web pages", kind: .connector,
                 summary: "Reads the text of a public https page, such as documentation.",
                 manifest: "", connectorID: "web"),

        ShopItem(id: "security-review", name: "Security review", kind: .skill,
                 summary: "Looks for injection, secrets in code, and unsafe file or shell use.",
                 manifest: securityReview, connectorID: nil),
        ShopItem(id: "performance-review", name: "Performance review", kind: .skill,
                 summary: "Looks for repeated work in loops, blocking calls, and large copies.",
                 manifest: performanceReview, connectorID: nil),
        ShopItem(id: "explain-api", name: "Explain an API", kind: .skill,
                 summary: "Explains an API from its documentation page. Mention !web to let it read pages.",
                 manifest: explainAPI, connectorID: nil),
        ShopItem(id: "accessibility-pass", name: "Accessibility pass", kind: .skill,
                 summary: "Checks HTML for missing alt text, unlabeled fields, heading order, and small tap targets.",
                 manifest: accessibilityPass, connectorID: nil),
    ]

    static func manifest(of item: ShopItem) -> PluginManifest? {
        guard item.kind != .connector else { return nil }
        return try? JSONDecoder().decode(PluginManifest.self, from: Data(item.manifest.utf8))
    }

    /// What adding the item does, shown before the user confirms.
    static func permissions(of item: ShopItem) -> [String] {
        switch item.kind {
        case .connector:
            return ["Turns on the \(item.name) connector for this chat. It only reads."]
        case .plugin, .skill:
            guard let manifest = manifest(of: item) else { return ["Adds nothing."] }
            var lines: [String] = []
            if let skills = manifest.skills, !skills.isEmpty {
                lines.append("Adds \(skills.count) skill(s): " + skills.map(\.name).joined(separator: ", "))
            }
            if let commands = manifest.commands, !commands.isEmpty {
                lines.append("Allows commands, sandboxed with no network: " + commands.joined(separator: ", "))
            }
            return lines.isEmpty ? ["Adds nothing."] : lines
        }
    }

    static func isInstalled(_ item: ShopItem, in directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder(for: item, in: directory).appendingPathComponent("plugin.json").path)
    }

    static func install(_ item: ShopItem, into directory: URL) throws {
        guard item.kind != .connector else { return }
        let folder = folder(for: item, in: directory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try item.manifest.write(to: folder.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)
    }

    static func remove(_ item: ShopItem, from directory: URL) throws {
        let folder = folder(for: item, in: directory)
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
    }

    private static func folder(for item: ShopItem, in directory: URL) -> URL {
        directory.appendingPathComponent(item.id, isDirectory: true)
    }

    private static let swiftDeveloper = #"""
    {
      "name": "swift-dev",
      "description": "SwiftUI review and Xcode project listing.",
      "skills": [
        {"id": "swiftui-review", "name": "SwiftUI review", "instructions": "Review SwiftUI views for state owned in the wrong place, work done inside body, missing accessibility labels, and layouts that break on small screens. Read the view files first, then report file and line."}
      ],
      "commands": ["xcodebuild -list"]
    }
    """#

    private static let releaseNotes = #"""
    {
      "name": "release-notes",
      "description": "Drafts release notes from tags and commits.",
      "skills": [
        {"id": "release-notes", "name": "Release notes", "instructions": "Draft release notes. Run git tag --list with run_command to find the latest tag, then git log --oneline with run_command for the commits since then. Group them under New, Changed, and Fixed, and keep each line short."}
      ],
      "commands": ["git tag --list", "git log --oneline"]
    }
    """#

    private static let nodeTools = #"""
    {
      "name": "node-tools",
      "description": "Runs the project's lint script and fixes what it reports.",
      "skills": [
        {"id": "lint-fix", "name": "Fix lint errors", "instructions": "Run npm run lint with run_command. For each reported error, read the file, make the smallest fix, and run npm run lint again. Report what is left, with file and line."}
      ],
      "commands": ["npm run lint"]
    }
    """#

    private static let securityReview = #"""
    {
      "name": "security-review",
      "description": "Security review skill.",
      "skills": [
        {"id": "security", "name": "Security review", "instructions": "Look for injection, secrets in code, unsafe file or shell use, and missing input checks. Read each file with read_file before judging it. Report each finding with file and line, most serious first."}
      ]
    }
    """#

    private static let performanceReview = #"""
    {
      "name": "performance-review",
      "description": "Performance review skill.",
      "skills": [
        {"id": "performance", "name": "Performance review", "instructions": "Look for work repeated inside loops, reads that could be batched, main-thread blocking, and large copies. Use search_text to find the call sites, read them, and report file and line with the likely cost."}
      ]
    }
    """#

    private static let explainAPI = #"""
    {
      "name": "explain-api",
      "description": "Explains an API from its documentation page.",
      "skills": [
        {"id": "explain-api", "name": "Explain an API", "instructions": "Explain the API the user names. If they give a documentation link, read it with web_fetch, which needs !web in the message. Otherwise say which page you would read. Give the signature, what each parameter does, and one short example. Mark anything you could not confirm from the page."}
      ]
    }
    """#

    private static let accessibilityPass = #"""
    {
      "name": "accessibility-pass",
      "description": "Accessibility checks for HTML pages.",
      "skills": [
        {"id": "accessibility", "name": "Accessibility pass", "instructions": "Check the HTML for images without alt text, form fields without labels, skipped heading levels, and tap targets under 24 px. Use search_text to find each one and report file and line before changing anything."}
      ]
    }
    """#
}

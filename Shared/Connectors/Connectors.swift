//
//  Connectors.swift
//  Gatita
//

import Foundation

/// A service Gatita can read. Like a plugin, a connector is named with "!" in a message (for example "!github"):
/// mentioning it turns its tools on for that message. Turning it on in Settings keeps it on for the whole chat.
nonisolated struct ConnectorInfo: Identifiable, Sendable {
    let id: String
    let name: String
    let summary: String
    let tools: [String]
    /// True when the connector needs the Mac host, such as GitHub through gh.
    let macOnly: Bool
}

nonisolated enum Connectors {
    static let catalog: [ConnectorInfo] = [
        ConnectorInfo(id: "github", name: "GitHub",
                      summary: "Reads pull requests, checks, and issues for this project's GitHub repo, through your gh login. Read-only.",
                      tools: ["github_list_prs", "github_view_pr", "github_pr_checks", "github_list_issues", "github_view_issue"],
                      macOnly: true),
        ConnectorInfo(id: "web", name: "Web pages",
                      summary: "Reads public https pages as text, and sends raw GET requests for APIs and JSON.",
                      tools: ["web_fetch", "web_curl"], macOnly: false),
        ConnectorInfo(id: "calendar", name: "Calendar",
                      summary: "Reads events from this Mac's calendars, through macOS calendar access. Read-only.",
                      tools: ["calendar_events"], macOnly: true),
    ]

    static func connector(named id: String) -> ConnectorInfo? {
        catalog.first { $0.id == id }
    }

    static func connector(for tool: String) -> ConnectorInfo? {
        catalog.first { $0.tools.contains(tool) }
    }

    /// Instruction lines for one connector's tools.
    static func toolHelp(for connector: ConnectorInfo) -> [String] {
        connector.tools.compactMap { helpLines[$0] }.map { "- " + $0 }
    }

    private static let helpLines: [String: String] = [
        "github_list_prs": #"{"tool": "github_list_prs", "state": "open, closed, merged, or all (optional, default open)"} lists pull requests in this project's GitHub repo."#,
        "github_view_pr": #"{"tool": "github_view_pr", "number": "<pull request number>"} shows one pull request as JSON."#,
        "github_pr_checks": #"{"tool": "github_pr_checks", "number": "<pull request number>"} shows its CI checks."#,
        "github_list_issues": #"{"tool": "github_list_issues", "state": "open, closed, or all (optional, default open)"} lists issues."#,
        "github_view_issue": #"{"tool": "github_view_issue", "number": "<issue number>"} shows one issue as JSON."#,
        "web_fetch": #"{"tool": "web_fetch", "url": "<https address>"} reads the text of a public https page, up to 20,000 characters."#,
        "web_curl": #"{"tool": "web_curl", "url": "<https address>"} sends a GET request and shows the status, the content type, and the body as text, up to 20,000 characters. Use it for APIs and JSON. Use web_fetch to read a page."#,
        "calendar_events": #"{"tool": "calendar_events", "start": "<day as YYYY-MM-DD, optional, default today>", "days": "<number of days, optional, default 7, up to 31>"} lists the events in that window, earliest first."#,
    ]

    /// Runs one connector tool. Web reads work on any platform; GitHub reads need the Mac host and gh.
    static func run(_ tool: String, arguments: [String: String], root: URL?) async throws -> String {
        if tool == "web_fetch" {
            return try await WebFetch.fetch(arguments["url"] ?? "")
        }
        if tool == "web_curl" {
            return try await WebCurl.fetch(arguments["url"] ?? "")
        }
        #if os(macOS)
        if tool == "calendar_events" {
            return try await CalendarConnector.run(arguments)
        }
        guard let root else { throw ToolError("set a project folder in Settings so GitHub knows which repository to read") }
        return try GitHubConnector.run(tool, arguments: arguments, root: root)
        #else
        throw ToolError("GitHub tools only run on the Mac host")
        #endif
    }

    /// Tool arguments as text. Numbers the model sends without quotes become their text.
    static func stringArguments(_ json: String) -> [String: String] {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return [:] }
        return object.mapValues { "\($0)" }
    }
}

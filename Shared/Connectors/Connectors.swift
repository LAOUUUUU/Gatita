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
        ConnectorInfo(id: "weather", name: "Weather",
                      summary: "Current weather and a forecast of up to 7 days for any place, from Open-Meteo. Sends the place name to open-meteo.com.",
                      tools: ["weather"], macOnly: false),
        ConnectorInfo(id: "wikipedia", name: "Wikipedia",
                      summary: "Searches Wikipedia and reads a page's summary, in any language. Sends the search words to wikipedia.org.",
                      tools: ["wikipedia_search", "wikipedia_page"], macOnly: false),
        ConnectorInfo(id: "dictionary", name: "Dictionary",
                      summary: "English definitions, examples, and synonyms, from dictionaryapi.dev.",
                      tools: ["define"], macOnly: false),
        ConnectorInfo(id: "currency", name: "Currency rates",
                      summary: "Daily exchange rates (European Central Bank reference rates), from frankfurter.dev.",
                      tools: ["exchange_rates"], macOnly: false),
        ConnectorInfo(id: "packages", name: "Packages",
                      summary: "The latest version, license, and links of a package on npm, PyPI, crates.io, or the Go module proxy.",
                      tools: ["package_info"], macOnly: false),
        ConnectorInfo(id: "stackoverflow", name: "Stack Overflow",
                      summary: "Searches Stack Overflow questions and reads their top answers, code included. About 300 reads a day.",
                      tools: ["stackoverflow_search", "stackoverflow_answers"], macOnly: false),
        ConnectorInfo(id: "repos", name: "Public GitHub repos",
                      summary: "Reads any public GitHub repository without a login: its facts, newest release, and README. 60 reads an hour.",
                      tools: ["repo_info", "repo_readme"], macOnly: false),
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
        "weather": #"{"tool": "weather", "place": "<city, optionally with its region or country, such as Toronto, Canada>", "days": "<1 to 7, optional, default 3>", "units": "<metric or imperial, optional, default metric>"} shows the weather now and a daily forecast."#,
        "wikipedia_search": #"{"tool": "wikipedia_search", "query": "<words>", "language": "<code such as en or fr, optional, default en>"} lists up to 5 matching Wikipedia pages with their titles."#,
        "wikipedia_page": #"{"tool": "wikipedia_page", "title": "<page title from wikipedia_search>", "language": "<optional, default en>"} reads the summary of one page, with its link."#,
        "define": #"{"tool": "define", "word": "<English word>"} gives its pronunciation, meanings by part of speech, examples, and synonyms."#,
        "exchange_rates": #"{"tool": "exchange_rates", "from": "<currency code such as USD>", "to": "<codes such as CAD, EUR, optional, default all>", "amount": "<number, optional, default 1>", "date": "<YYYY-MM-DD, optional, default latest>"} converts with that day's reference rates."#,
        "package_info": #"{"tool": "package_info", "registry": "npm, pypi, crates, or go", "name": "<package name or Go module path>"} shows the latest version, license, and links. Check versions with it instead of guessing them."#,
        "stackoverflow_search": #"{"tool": "stackoverflow_search", "query": "<question or error message>"} lists matching Stack Overflow questions with their scores and question numbers."#,
        "stackoverflow_answers": #"{"tool": "stackoverflow_answers", "id": "<question number>"} reads the top 3 answers to that question, code included. Say the answer came from Stack Overflow and give its link."#,
        "repo_info": #"{"tool": "repo_info", "repo": "<owner/name or a github.com link>"} shows a public repository's description, stars, language, license, last push, and newest release."#,
        "repo_readme": #"{"tool": "repo_readme", "repo": "<owner/name>"} reads its README, up to 20,000 characters."#,
    ]

    /// Runs one connector tool. Web reads and the public services work on any platform; GitHub and the calendar
    /// need the Mac host.
    static func run(_ tool: String, arguments: [String: String], root: URL?) async throws -> String {
        switch tool {
        case "web_fetch": return try await WebFetch.fetch(arguments["url"] ?? "")
        case "web_curl": return try await WebCurl.fetch(arguments["url"] ?? "")
        case "weather": return try await Weather.run(arguments)
        case "wikipedia_search", "wikipedia_page": return try await Wikipedia.run(tool, arguments: arguments)
        case "define": return try await DictionaryLookup.run(arguments)
        case "exchange_rates": return try await CurrencyRates.run(arguments)
        case "package_info": return try await PackageInfo.run(arguments)
        case "stackoverflow_search", "stackoverflow_answers": return try await StackOverflow.run(tool, arguments: arguments)
        case "repo_info", "repo_readme": return try await PublicGitHub.run(tool, arguments: arguments)
        default: break
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
        ToolArguments.parse(json) ?? [:]
    }
}

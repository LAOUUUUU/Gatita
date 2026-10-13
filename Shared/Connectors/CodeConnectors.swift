//
//  CodeConnectors.swift
//  Gatita
//

import Foundation

/// The latest version and the facts of a package, from the public registries: npm, PyPI, crates.io, and the
/// Go module proxy. No keys. It lets the model check a version instead of guessing it.
nonisolated enum PackageInfo {
    /// The registry for a name the model might use, such as "pip" for PyPI.
    static func registry(_ text: String) throws -> String {
        switch text.trimmingCharacters(in: .whitespaces).lowercased() {
        case "npm", "node", "nodejs", "javascript", "js", "typescript": return "npm"
        case "pypi", "pip", "python": return "pypi"
        case "crates", "crates.io", "crate", "cargo", "rust": return "crates"
        case "go", "golang": return "go"
        default: throw ToolError("registry must be npm, pypi, crates, or go")
        }
    }

    static func url(registry text: String, name: String) throws -> URL {
        let registry = try registry(text)
        let package = name.trimmingCharacters(in: .whitespaces)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "@/._-~"))
        guard !package.isEmpty, !package.contains(".."), package.unicodeScalars.allSatisfy(allowed.contains) else {
            throw ToolError("\(name) is not a package name")
        }
        switch registry {
        case "npm":
            // A scoped package has one slash, after its @scope.
            guard package.filter({ $0 == "/" }).count <= (package.hasPrefix("@") ? 1 : 0) else {
                throw ToolError("\(name) is not an npm package name")
            }
            return try PublicAPI.url("https://registry.npmjs.org/\(package)/latest")
        case "pypi":
            guard !package.contains("/") else { throw ToolError("\(name) is not a PyPI package name") }
            return try PublicAPI.url("https://pypi.org/pypi/\(package)/json")
        case "crates":
            guard !package.contains("/") else { throw ToolError("\(name) is not a crate name") }
            return try PublicAPI.url("https://crates.io/api/v1/crates/\(package)")
        default:
            return try PublicAPI.url("https://proxy.golang.org/\(goEscaped(package))/@latest")
        }
    }

    /// The Go module proxy's case encoding: each capital letter becomes "!" and the lowercase letter.
    static func goEscaped(_ path: String) -> String {
        path.map { $0.isUppercase ? "!" + $0.lowercased() : String($0) }.joined()
    }

    static func render(registry text: String, data: Data, name: String = "") throws -> String {
        let registry = try registry(text)
        let object = try PublicAPI.requireObject(data, service: registry)
        var lines: [String] = []
        func add(_ label: String, _ value: Any?) {
            if let text = value as? String, !text.isEmpty {
                lines.append("\(label): \(text)")
            } else if let number = value as? NSNumber {
                lines.append("\(label): \(number)")
            }
        }

        switch registry {
        case "npm":
            lines.append("npm package \((object["name"] as? String) ?? name)")
            add("Latest version", object["version"])
            add("Description", object["description"])
            add("License", (object["license"] as? String) ?? ((object["license"] as? [String: Any])?["type"] as? String))
            add("Homepage", object["homepage"])
            let repository = (object["repository"] as? String) ?? ((object["repository"] as? [String: Any])?["url"] as? String)
            add("Repository", repository.map(cleanRepository))
        case "pypi":
            let info = (object["info"] as? [String: Any]) ?? [:]
            lines.append("PyPI package \((info["name"] as? String) ?? name)")
            add("Latest version", info["version"])
            let released = ((object["urls"] as? [[String: Any]])?.first?["upload_time_iso_8601"] as? String).map(PublicAPI.day)
            add("Released", released)
            add("Description", info["summary"])
            let license = ((info["license_expression"] as? String) ?? (info["license"] as? String))?
                .components(separatedBy: .newlines).first.map { String($0.prefix(120)) }
            add("License", license)
            add("Python", info["requires_python"])
            add("Homepage", info["home_page"])
            for (label, address) in ((info["project_urls"] as? [String: String]) ?? [:]).sorted(by: { $0.key < $1.key }).prefix(4) {
                add(label, address)
            }
        case "crates":
            let crate = (object["crate"] as? [String: Any]) ?? [:]
            lines.append("crates.io package \((crate["name"] as? String) ?? name)")
            add("Latest version", (crate["max_stable_version"] as? String) ?? (crate["newest_version"] as? String))
            add("Updated", (crate["updated_at"] as? String).map(PublicAPI.day))
            add("Description", (crate["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines))
            add("Repository", crate["repository"])
            add("Homepage", crate["homepage"])
            add("Downloads", crate["downloads"])
        default:
            lines.append(name.isEmpty ? "Go module" : "Go module \(name)")
            add("Latest version", object["Version"])
            add("Released", (object["Time"] as? String).map(PublicAPI.day))
            add("Source", (object["Origin"] as? [String: Any])?["URL"])
        }
        return lines.joined(separator: "\n")
    }

    /// "git+https://github.com/a/b.git" becomes "https://github.com/a/b".
    private static func cleanRepository(_ address: String) -> String {
        var text = address
        if text.hasPrefix("git+") { text.removeFirst(4) }
        if text.hasPrefix("git://") { text = "https://" + text.dropFirst(6) }
        if text.hasPrefix("git@github.com:") { text = "https://github.com/" + text.dropFirst(15) }
        if text.hasSuffix(".git") { text.removeLast(4) }
        return text
    }

    static func run(_ arguments: [String: String]) async throws -> String {
        let registry = try registry(arguments["registry"] ?? arguments["ecosystem"] ?? "npm")
        let name = arguments["name"] ?? arguments["package"] ?? ""
        let data = try await PublicAPI.getOK(try url(registry: registry, name: name), service: registry,
                                             notFound: "no package called \(name) on \(registry)")
        return try render(registry: registry, data: data, name: name)
    }
}

/// Stack Overflow search and answers, through the Stack Exchange API. No key; it allows about 300 reads a day
/// from one address without one. Answers are shared under CC BY-SA, so each result carries its link.
nonisolated enum StackOverflow {
    private static let base = "https://api.stackexchange.com/2.3"

    static func searchURL(_ query: String) throws -> URL {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ToolError("give something to search for, such as an error message") }
        return try PublicAPI.url(base, path: "/search/advanced", query: [
            ("order", "desc"), ("sort", "relevance"), ("q", text), ("site", "stackoverflow"),
            ("pagesize", "8"), ("filter", "default"),
        ])
    }

    static func answersURL(_ id: String) throws -> URL {
        let number = id.trimmingCharacters(in: .whitespaces)
        guard !number.isEmpty, number.allSatisfy(\.isNumber) else { throw ToolError("id must be a question number") }
        return try PublicAPI.url(base, path: "/questions/\(number)/answers", query: [
            ("order", "desc"), ("sort", "votes"), ("site", "stackoverflow"), ("pagesize", "3"), ("filter", "withbody"),
        ])
    }

    /// The items of an answer, or the error Stack Exchange sent instead.
    private static func items(_ data: Data) throws -> [[String: Any]] {
        let object = try PublicAPI.requireObject(data, service: "Stack Overflow")
        if let message = object["error_message"] as? String {
            throw ToolError("Stack Overflow said: \(message)")
        }
        return (object["items"] as? [[String: Any]]) ?? []
    }

    static func renderSearch(_ data: Data, query: String) throws -> String {
        let questions = try items(data)
        guard !questions.isEmpty else { return "No Stack Overflow questions match \"\(query)\"." }
        var lines = ["Stack Overflow questions for \"\(query)\":"]
        for (index, question) in questions.enumerated() {
            let title = PublicAPI.decodeEntities((question["title"] as? String) ?? "?")
            let id = (question["question_id"] as? NSNumber)?.stringValue ?? "?"
            lines.append("\(index + 1). \(title) (question \(id))")
            let answers = (question["answer_count"] as? NSNumber)?.intValue ?? 0
            var facts = ["score \((question["score"] as? NSNumber)?.intValue ?? 0)", answers == 1 ? "1 answer" : "\(answers) answers"]
            if question["accepted_answer_id"] != nil { facts.append("accepted answer") }
            lines.append("   " + facts.joined(separator: ", "))
            if let tags = question["tags"] as? [String], !tags.isEmpty {
                lines.append("   tags: " + tags.joined(separator: ", "))
            }
            if let link = question["link"] as? String {
                lines.append("   " + link)
            }
        }
        lines.append("Read the answers to one with stackoverflow_answers and its question number.")
        return lines.joined(separator: "\n")
    }

    static func renderAnswers(_ data: Data, questionID: String) throws -> String {
        let answers = try items(data)
        let source = "Source: https://stackoverflow.com/q/\(questionID) (Stack Overflow, CC BY-SA)"
        guard !answers.isEmpty else { return "Question \(questionID) has no answers yet.\n\(source)" }
        var sections: [String] = []
        for (index, answer) in answers.enumerated() {
            let score = (answer["score"] as? NSNumber)?.intValue ?? 0
            let accepted = (answer["is_accepted"] as? Bool) == true ? ", accepted" : ""
            sections.append("## Answer \(index + 1) (score \(score)\(accepted))\n\n" + text(fromHTML: (answer["body"] as? String) ?? ""))
        }
        return PublicAPI.capped(sections.joined(separator: "\n\n"), 15_000) + "\n\n" + source
    }

    /// An answer's HTML as Markdown-like text: code blocks fenced, inline code in backticks, paragraphs and list
    /// items on their own lines. Code is set aside first, so its "<" and "&" survive the tag removal.
    static func text(fromHTML html: String) -> String {
        var kept: [String] = []
        func setAside(_ text: String, pattern: String, wrap: (String) -> String) -> String {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
            var result = ""
            var last = text.startIndex
            for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let whole = Range(match.range, in: text), let inner = Range(match.range(at: 1), in: text) else { continue }
                result += text[last..<whole.lowerBound]
                kept.append(wrap(PublicAPI.stripTags(String(text[inner]))))
                result += "\u{1}\(kept.count - 1)\u{1}"
                last = whole.upperBound
            }
            return result + text[last...]
        }
        var text = setAside(html, pattern: #"(?s)<pre[^>]*>\s*<code[^>]*>(.*?)</code>\s*</pre>"#) { code in
            "\n\n```\n" + code.trimmingCharacters(in: .newlines) + "\n```\n\n"
        }
        text = setAside(text, pattern: #"(?s)<code[^>]*>(.*?)</code>"#) { "`\($0)`" }
        text = PublicAPI.replace(text, #"(?i)<br\s*/?>"#, with: "\n")
        text = PublicAPI.replace(text, #"(?i)</(p|h[1-6]|blockquote|ul|ol)>"#, with: "\n\n")
        text = PublicAPI.replace(text, #"(?i)<li[^>]*>"#, with: "- ")
        text = PublicAPI.replace(text, #"(?i)</li>"#, with: "\n")
        text = PublicAPI.stripTags(text)
        for (index, piece) in kept.enumerated().reversed() {
            text = text.replacingOccurrences(of: "\u{1}\(index)\u{1}", with: piece)
        }
        text = PublicAPI.replace(text, #"\n[ \t]+\n"#, with: "\n\n")
        text = PublicAPI.replace(text, #"\n{3,}"#, with: "\n\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func run(_ tool: String, arguments: [String: String]) async throws -> String {
        if tool == "stackoverflow_search" {
            let query = arguments["query"] ?? ""
            let (data, _) = try await PublicAPI.get(try searchURL(query))
            return try renderSearch(data, query: query)
        }
        let id = arguments["id"] ?? arguments["question"] ?? ""
        let (data, _) = try await PublicAPI.get(try answersURL(id))
        return try renderAnswers(data, questionID: id.trimmingCharacters(in: .whitespaces))
    }
}

/// Any public GitHub repository, read without a login through GitHub's REST API: its facts, newest release,
/// and README. GitHub allows 60 such reads an hour from one address. The project's own repo, through the
/// gh login, is the GitHub connector.
nonisolated enum PublicGitHub {
    /// "owner/name" from that text or from a github.com link.
    static func repoPath(_ text: String) throws -> String {
        var path = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var fromLink = false
        for prefix in ["https://github.com/", "http://github.com/", "github.com/"] where path.lowercased().hasPrefix(prefix) {
            path = String(path.dropFirst(prefix.count))
            fromLink = true
        }
        var parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if fromLink { parts = Array(parts.prefix(2)) }
        if parts.count == 2, parts[1].hasSuffix(".git") { parts[1].removeLast(4) }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.unicodeScalars.allSatisfy(allowed.contains) }) else {
            throw ToolError("give the repository as owner/name, such as apple/swift")
        }
        return parts.joined(separator: "/")
    }

    static func renderRepo(_ data: Data, releases: Data?) throws -> String {
        let repo = try PublicAPI.requireObject(data, service: "GitHub")
        let name = (repo["full_name"] as? String) ?? "?"
        var lines = [name + ((repo["description"] as? String).map { ": " + $0 } ?? "")]
        if let address = repo["html_url"] as? String { lines.append(address) }
        let count = { (key: String) in (repo[key] as? NSNumber)?.intValue ?? 0 }
        lines.append("Stars: \(count("stargazers_count")) · Forks: \(count("forks_count")) · Open issues: \(count("open_issues_count"))")
        if let language = repo["language"] as? String { lines.append("Language: \(language)") }
        if let license = (repo["license"] as? [String: Any])?["spdx_id"] as? String, license != "NOASSERTION" {
            lines.append("License: \(license)")
        }
        if let branch = repo["default_branch"] as? String { lines.append("Default branch: \(branch)") }
        if let pushed = repo["pushed_at"] as? String { lines.append("Last push: \(PublicAPI.day(pushed))") }
        if let homepage = repo["homepage"] as? String, !homepage.isEmpty { lines.append("Homepage: \(homepage)") }
        if repo["archived"] as? Bool == true { lines.append("This repository is archived (read-only).") }

        if let releases, let newest = (PublicAPI.array(releases) as? [[String: Any]])?.first,
           let tag = newest["tag_name"] as? String {
            var line = "Newest release: \(tag)"
            if let title = newest["name"] as? String, !title.isEmpty, title != tag { line += " (\(title))" }
            if newest["prerelease"] as? Bool == true { line += ", a pre-release" }
            if let published = newest["published_at"] as? String { line += ", published \(PublicAPI.day(published))" }
            lines.append(line)
        } else if releases != nil {
            lines.append("No releases yet.")
        }
        return lines.joined(separator: "\n")
    }

    private static func check(_ status: Int, _ data: Data, missing: String) throws {
        if (200..<300).contains(status) { return }
        if status == 404 { throw ToolError(missing) }
        if status == 403 || status == 429 {
            throw ToolError("GitHub's limit of 60 reads an hour without a login was reached. Try again later.")
        }
        throw ToolError("GitHub answered HTTP \(status)\(PublicAPI.reason(in: data).map { ": \($0)" } ?? "")")
    }

    static func run(_ tool: String, arguments: [String: String]) async throws -> String {
        let path = try repoPath(arguments["repo"] ?? arguments["repository"] ?? "")
        let base = "https://api.github.com/repos/" + path
        if tool == "repo_readme" {
            let (data, status) = try await PublicAPI.get(try PublicAPI.url(base + "/readme"), accept: "application/vnd.github.raw+json")
            try check(status, data, missing: "\(path) has no README, or it is not a public repository")
            return "README of \(path):\n\n" + PublicAPI.capped(String(decoding: data, as: UTF8.self))
        }
        let (data, status) = try await PublicAPI.get(try PublicAPI.url(base), accept: "application/vnd.github+json")
        try check(status, data, missing: "no public repository is called \(path). It may be private, or the name may be wrong.")
        // The list holds pre-releases too, which /releases/latest leaves out.
        let releases = try? await PublicAPI.get(try PublicAPI.url(base + "/releases", query: [("per_page", "1")]),
                                                accept: "application/vnd.github+json")
        return try renderRepo(data, releases: releases.flatMap { (200..<300).contains($0.status) ? $0.data : nil })
    }
}

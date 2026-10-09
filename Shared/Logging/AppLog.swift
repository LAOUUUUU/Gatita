//
//  AppLog.swift
//  Gatita
//

import Foundation

/// A plain-text log and Markdown failure reports, kept in the app's folder on this Mac.
/// The model can read them back with list_reports and read_report.
nonisolated struct AppLog: Sendable {
    static let maxLogBytes = 1_000_000

    let directory: URL

    /// ~/Library/Application Support/Gatita/logs
    static var defaultDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Gatita/logs", isDirectory: true)
    }

    var logFile: URL {
        directory.appendingPathComponent("gatita.log")
    }

    func info(_ message: String) {
        write("INFO", message)
    }

    func error(_ message: String) {
        write("ERROR", message)
    }

    /// Writes a report into failures/ and returns its path relative to the logs folder.
    @discardableResult
    func recordFailure(kind: String, message: String, details: [String]) -> String? {
        let folder = directory.appendingPathComponent("failures", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let safeKind = kind.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let name = "\(stamp)-\(safeKind)-\(UUID().uuidString.prefix(6)).md"
        let context = details.map { "- \($0)" }.joined(separator: "\n")
        let body = """
        # Failure: \(kind)

        Time: \(stamp)

        ## Error

        \(message)

        ## Context

        \(context)

        """
        do {
            try body.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
        } catch {
            return nil
        }
        self.error("failure recorded: failures/\(name)")
        return "failures/" + name
    }

    private func write(_ level: String, _ message: String) {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if let size = (try? fileManager.attributesOfItem(atPath: logFile.path)[.size]) as? Int,
           size > Self.maxLogBytes {
            try? fileManager.removeItem(at: directory.appendingPathComponent("gatita.log.1"))
            try? fileManager.moveItem(at: logFile, to: directory.appendingPathComponent("gatita.log.1"))
        }
        if !fileManager.fileExists(atPath: logFile.path) {
            fileManager.createFile(atPath: logFile.path, contents: nil)
        }

        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(stamp) [\(level)] \(message)\n"
        guard let data = line.data(using: .utf8), let handle = try? FileHandle(forWritingTo: logFile) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }
}

/// Counts events such as tool calls and failures in a local JSON file. Nothing is sent anywhere.
nonisolated struct Analytics: Sendable {
    let file: URL

    init(file: URL) {
        self.file = file
    }

    /// ~/Library/Application Support/Gatita/logs/analytics.json
    static var defaultFile: URL {
        AppLog.defaultDirectory.appendingPathComponent("analytics.json")
    }

    func count(_ event: String) {
        var counts = summary()
        counts[event, default: 0] += 1
        guard let data = try? JSONEncoder().encode(counts) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    func summary() -> [String: Int] {
        guard let data = try? Data(contentsOf: file),
              let counts = try? JSONDecoder().decode([String: Int].self, from: data) else { return [:] }
        return counts
    }
}

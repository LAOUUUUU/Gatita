//
//  ActivityStatus.swift
//  Gatita
//

import Foundation

/// Where a tool call stands: still running, finished, or finished with an error.
enum ActivityStatus: Equatable {
    case running
    case done
    case failed
}

extension ToolActivity {
    var status: ActivityStatus {
        guard let result else { return .running }
        return result.hasPrefix("error:") ? .failed : .done
    }

    /// How long the call took, once it has finished.
    var duration: TimeInterval? {
        guard let startedAt, let finishedAt else { return nil }
        return finishedAt.timeIntervalSince(startedAt)
    }

    /// The SF Symbol that stands for this kind of tool.
    var symbol: String {
        switch name {
        case "run_command": "terminal"
        case "read_file", "list_files": "doc.text"
        case "search_text": "magnifyingglass"
        case "write_file", "edit_file": "pencil.line"
        case "git_status", "git_diff": "arrow.triangle.branch"
        case "web_fetch", "web_curl", "web_check": "globe"
        case "list_reports", "read_report": "exclamationmark.bubble"
        case "ask_user": "questionmark.bubble"
        case "calendar_events": "calendar"
        default: name.hasPrefix("github_") ? "arrow.triangle.pull" : "wrench.and.screwdriver"
        }
    }
}

/// "0.4 s" for quick calls, "1m 12s" for longer ones.
enum ActivityFormat {
    static func duration(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return String(format: "%.1f s", seconds)
        }
        return "\(Int(seconds) / 60)m \(Int(seconds) % 60)s"
    }
}

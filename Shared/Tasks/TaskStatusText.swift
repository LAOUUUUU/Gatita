//
//  TaskStatusText.swift
//  Gatita
//

import Foundation

/// The wait and the note for task_status. A running task is waited on, so the model doesn't poll in a tight loop.
nonisolated enum TaskStatusText {
    /// How long task_status waits for a running task, from the model's "wait" argument.
    /// Default 20 seconds, never less than 0 and never more than 60.
    static func waitSeconds(_ text: String?) -> Double {
        guard let text, let value = Double(text.trimmingCharacters(in: .whitespaces)) else { return 20 }
        return min(max(value, 0), 60)
    }

    /// What task_status tells the model after the wait: keep checking a running task, or answer when it has finished.
    static func note(running: Bool) -> String {
        running
            ? "It is still running. Call task_status again to wait longer."
            : "It has finished. Report the result now, and do not check it again."
    }
}

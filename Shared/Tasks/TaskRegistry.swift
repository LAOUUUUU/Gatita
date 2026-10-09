//
//  TaskRegistry.swift
//  Gatita
//

import Foundation
import Observation

/// A command that runs in the background, past the reply that started it.
struct BackgroundTask: Identifiable, Equatable {
    enum Status: Equatable {
        case running
        case done
        case failed
        case stopped
    }

    let id: String
    let command: String
    var status: Status
    var output: String
    var exitCode: Int32?
    let startedAt: Date
    var finishedAt: Date?
}

/// A subagent: Gatita working on one task in a separate, read-only run.
struct Subagent: Identifiable, Equatable {
    enum Status: Equatable {
        case running
        case done
        case failed
    }

    let id: String
    let task: String
    var status: Status
    var result: String?
    let startedAt: Date
    var finishedAt: Date?
}

/// Background commands and subagents for this run of the app. The activity panel shows them, and the model
/// starts, checks, stops, and collects them with tools.
@MainActor
@Observable
final class TaskRegistry {
    static let maxOutputCharacters = 20_000

    private(set) var background: [BackgroundTask] = []
    private(set) var agents: [Subagent] = []
    #if os(macOS)
    @ObservationIgnored private var processes: [String: BackgroundProcess] = [:]
    #endif
    @ObservationIgnored private var agentJobs: [String: Task<String, Never>] = [:]
    private var counter = 0

    private func nextID(_ prefix: String) -> String {
        counter += 1
        return "\(prefix)\(counter)"
    }

    func backgroundTask(_ id: String) -> BackgroundTask? {
        background.first { $0.id == id }
    }

    #if os(macOS)
    /// Starts one allowed command in the background and returns its id. Its output arrives as it is written.
    func startBackground(_ argv: [String], command: String, in root: URL) throws -> String {
        let id = nextID("b")
        let process = BackgroundProcess(arguments: argv, root: root)
        try process.start(
            onOutput: { [weak self] text in
                Task { @MainActor in self?.appendOutput(id, text) }
            },
            onExit: { [weak self] code in
                Task { @MainActor in self?.finishBackground(id, exitCode: code) }
            })
        processes[id] = process
        background.append(BackgroundTask(id: id, command: command, status: .running, output: "",
                                         exitCode: nil, startedAt: Date(), finishedAt: nil))
        return id
    }

    /// Stops a running background command. Returns false when it is not running.
    func stopBackground(_ id: String) -> Bool {
        guard let process = processes[id], let index = background.firstIndex(where: { $0.id == id }) else {
            return false
        }
        background[index].status = .stopped
        process.stop()
        return true
    }
    #else
    func startBackground(_ argv: [String], command: String, in root: URL) throws -> String {
        throw ToolError("background commands only run on the Mac")
    }

    func stopBackground(_ id: String) -> Bool {
        false
    }
    #endif

    /// Starts a subagent on one task and returns its id. Its answer is collected with `agentResult`.
    func spawnAgent(task: String, client: GatitaClient) -> String {
        let id = nextID("a")
        agents.append(Subagent(id: id, task: task, status: .running, result: nil, startedAt: Date(), finishedAt: nil))
        agentJobs[id] = Task {
            do {
                let answer = try await client.send(messages: [ChatMessage(role: "user", content: task)])
                self.finishAgent(id, result: answer, status: .done)
                return answer
            } catch {
                let message = "error: \(error.localizedDescription)"
                self.finishAgent(id, result: message, status: .failed)
                return message
            }
        }
        return id
    }

    /// A subagent's answer. Waits for it when it is still running.
    func agentResult(_ id: String) async -> String {
        guard let job = agentJobs[id] else { return "error: no subagent with id \(id)" }
        return await job.value
    }

    private func appendOutput(_ id: String, _ text: String) {
        guard let index = background.firstIndex(where: { $0.id == id }) else { return }
        var output = background[index].output + text
        if output.count > Self.maxOutputCharacters {
            output = String(output.suffix(Self.maxOutputCharacters))
        }
        background[index].output = output
    }

    #if os(macOS)
    private func finishBackground(_ id: String, exitCode: Int32) {
        processes[id] = nil
        guard let index = background.firstIndex(where: { $0.id == id }) else { return }
        background[index].exitCode = exitCode
        background[index].finishedAt = Date()
        if background[index].status == .running {
            background[index].status = exitCode == 0 ? .done : .failed
        }
    }
    #endif

    private func finishAgent(_ id: String, result: String, status: Subagent.Status) {
        agentJobs[id] = nil
        guard let index = agents.firstIndex(where: { $0.id == id }) else { return }
        agents[index].result = result
        agents[index].status = status
        agents[index].finishedAt = Date()
    }
}

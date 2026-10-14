//
//  GatitaIntents.swift
//  Gatita
//

import AppIntents
import Foundation

/// The checks and text behind "Ask Gatita" in Shortcuts and Siri, kept apart from App Intents so they can be tested.
nonisolated enum IntentAnswer {
    /// The most Siri reads out. The whole answer is still the shortcut's result.
    static let maxSpoken = 300

    struct Problem: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func check(question: String, key: String, online: Bool) throws {
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Problem(message: "Say or type a question for Gatita.")
        }
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Problem(message: "Add your Gatita API key in Gatita's Settings first.")
        }
        guard online else { throw Problem(message: NoInternet.headline) }
    }

    /// The answer as Siri should say it: words only, no Markdown or code, and short.
    static func spoken(_ answer: String) -> String {
        let plain = SpeechText.plain(from: answer)
        guard plain.count > maxSpoken else { return plain }
        return String(plain.prefix(maxSpoken)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// The answer, and each tool call's result, so the caller can say when memory changed.
    static func ask(_ question: String, with client: GatitaClient) async throws
        -> (answer: String, toolCalls: [(tool: String, result: String)]) {
        var calls: [(tool: String, result: String)] = []
        let answer = try await client.stream(messages: [ChatMessage(role: "user", content: question)]) { event in
            if case .toolFinished(_, let name, let result) = event { calls.append((name, result)) }
        }
        return (answer, calls)
    }
}

/// Reaches the running app's chat from an intent. The app sets `viewModel` as it starts.
@MainActor
enum IntentBridge {
    static weak var viewModel: ChatViewModel?

    /// Waits a moment for the app to finish starting when the intent launched it.
    static func waitForApp() async throws -> ChatViewModel {
        for _ in 0..<30 where viewModel == nil {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        guard let viewModel else {
            throw IntentAnswer.Problem(message: "Gatita is still starting. Try again in a moment.")
        }
        return viewModel
    }
}

/// "Ask Gatita": a question in, Gatita's answer out, in Chat mode with your connectors and memory. The question and
/// answer are also saved as a chat in Gatita.
struct AskGatitaIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Gatita"
    static var description: IntentDescription? {
        IntentDescription("Asks Gatita a question and returns the answer. The question and answer are saved as a chat in Gatita.")
    }

    @Parameter(title: "Question", requestValueDialog: "What do you want to ask Gatita?")
    var question: String

    static var parameterSummary: some ParameterSummary {
        Summary("Ask Gatita \(\.$question)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let viewModel = try await IntentBridge.waitForApp()
        let answer = try await viewModel.answerFromShortcut(question)
        return .result(value: answer, dialog: IntentDialog(stringLiteral: IntentAnswer.spoken(answer)))
    }
}

#if os(macOS)
/// Opens the quick panel, as ⌃⌘G does.
nonisolated struct OpenQuickPanelIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Gatita's Quick Panel"
    static var supportedModes: IntentModes { .foreground }

    func perform() async throws -> some IntentResult {
        let viewModel = try await IntentBridge.waitForApp()
        await MainActor.run { QuickPanelController.shared.show(viewModel) }
        return .result()
    }
}
#endif

/// The shortcuts Gatita offers in the Shortcuts app and to Siri, with no setup.
nonisolated struct GatitaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AskGatitaIntent(),
                    phrases: ["Ask \(.applicationName)", "Ask \(.applicationName) a question"],
                    shortTitle: "Ask Gatita",
                    systemImageName: "bubble.left.and.text.bubble.right")
        #if os(macOS)
        AppShortcut(intent: OpenQuickPanelIntent(),
                    phrases: ["Open the \(.applicationName) quick panel"],
                    shortTitle: "Quick Panel",
                    systemImageName: "command")
        #endif
    }
}

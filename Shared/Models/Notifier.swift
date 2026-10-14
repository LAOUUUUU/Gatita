//
//  Notifier.swift
//  Gatita
//

import Foundation
import Observation
import UserNotifications
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// What a notification says. Made here, apart from the system calls, so it can be tested.
enum Notifier {
    struct Note: Equatable {
        let title: String
        let body: String
    }

    static let maxBodyLength = 140

    /// A finished reply: the chat's title, and the reply's first line without Markdown or code.
    static func replyFinished(chatTitle: String, reply: String) -> Note {
        let firstLine = SpeechText.plain(from: reply)
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && $0 != "Code block skipped." && $0 != "Chart skipped." }
        return Note(title: chatTitle, body: shortened(firstLine ?? "Gatita finished replying."))
    }

    static func question(chatTitle: String, question: String) -> Note {
        Note(title: "Gatita asks: \(chatTitle)", body: shortened(question))
    }

    static func failed(chatTitle: String, reason: String) -> Note {
        Note(title: "Gatita's reply failed: \(chatTitle)", body: shortened(reason))
    }

    /// A scheduled prompt finished: its name, and the answer's first line.
    static func scheduledFinished(name: String, reply: String) -> Note {
        Note(title: "Scheduled: \(name)", body: replyFinished(chatTitle: name, reply: reply).body)
    }

    /// A command waiting for your answer while Gatita is not in front.
    static func commandWaiting(chatTitle: String, command: String) -> Note {
        Note(title: "Gatita wants to run a command", body: shortened("\(command), in \(chatTitle). Allow or deny it in Gatita."))
    }

    static func backgroundTaskFinished(command: String, exitCode: Int32, seconds: TimeInterval) -> Note {
        let took = ActivityFormat.duration(seconds)
        return exitCode == 0
            ? Note(title: "Background task finished", body: shortened("\(command) finished in \(took)."))
            : Note(title: "Background task failed", body: shortened("\(command) exited with code \(exitCode) after \(took)."))
    }

    private static func shortened(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxBodyLength else { return trimmed }
        return String(trimmed.prefix(maxBodyLength)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// Sends Gatita's system notifications. Only while Gatita is not the app in front: when you are looking at the
/// chat, a notification would only repeat what is on screen. Clicking one opens its chat.
@MainActor
final class ReplyNotifier: NSObject, UNUserNotificationCenterDelegate {
    /// Opens a saved chat when its notification is clicked.
    var onOpenChat: ((UUID) -> Void)?
    private var asked = false
    private static let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    override init() {
        super.init()
        if !Self.isTesting { UNUserNotificationCenter.current().delegate = self }
    }

    /// Asks for permission to notify, once, the first time a message is sent.
    func prepare() {
        guard !asked, !Self.isTesting else { return }
        asked = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Posts the note, unless Gatita is the app in front. With `always`, it is posted either way, as for a
    /// scheduled prompt, which finishes on its own.
    func post(_ note: Notifier.Note, chatID: UUID? = nil, always: Bool = false) {
        guard !Self.isTesting, always || !Self.appIsInFront else { return }
        let content = UNMutableNotificationContent()
        content.title = note.title
        content.body = note.body
        content.sound = .default
        var info: [String: Any] = ["always": always]
        if let chatID { info["chatID"] = chatID.uuidString }
        content.userInfo = info
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private static var appIsInFront: Bool {
        #if os(macOS)
        NSApplication.shared.isActive
        #else
        UIApplication.shared.applicationState == .active
        #endif
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let text = response.notification.request.content.userInfo["chatID"] as? String,
              let id = UUID(uuidString: text) else { return }
        await MainActor.run {
            onOpenChat?(id)
            #if os(macOS)
            NSApplication.shared.activate()
            #endif
        }
    }

    /// A notification that arrives while Gatita is in front is not shown, since the chat is already on screen,
    /// except one posted with `always`, which shows as a banner.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        notification.request.content.userInfo["always"] as? Bool == true ? [.banner, .sound] : []
    }
}

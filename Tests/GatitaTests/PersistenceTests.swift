//
//  PersistenceTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// What Gatita keeps on the Mac: the Keychain key, the settings file, chat history, logs, reports, and analytics.
final class PersistenceTests: XCTestCase {
    // MARK: - Keychain

    func testKeychainSavesReadsOverwritesAndDeletesTheKey() {
        let account = "tests-\(UUID().uuidString)"
        XCTAssertTrue(KeychainStore.save("gatita_test_123", account: account))
        XCTAssertEqual(KeychainStore.read(account: account), "gatita_test_123")
        XCTAssertTrue(KeychainStore.save("gatita_test_456", account: account))
        XCTAssertEqual(KeychainStore.read(account: account), "gatita_test_456")
        XCTAssertTrue(KeychainStore.delete(account: account))
        XCTAssertNil(KeychainStore.read(account: account))
    }

    // MARK: - Settings file

    func testSettingsSurviveARelaunchAndHoldNoAPIKey() throws {
        let folder = temporaryFolder(self)
        let file = folder.appendingPathComponent("settings.json")
        var saved = AppSettings()
        saved.projectRoot = "~/Documents/Gatita"
        saved.model = "gatita-7.1-mini"
        saved.connectors = ["github"]
        saved.allowWrites = true
        SettingsStore.save(saved, to: file)
        XCTAssertEqual(SettingsStore.load(from: file), saved)

        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertFalse(text.lowercased().contains("apikey"))
        XCTAssertFalse(text.contains("gatita-api-key"))
    }

    func testMissingOrBrokenSettingsFallBackToDefaults() throws {
        let folder = temporaryFolder(self)
        XCTAssertEqual(SettingsStore.load(from: folder.appendingPathComponent("nope.json")), AppSettings())
        let file = folder.appendingPathComponent("settings.json")
        try "{ broken".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(SettingsStore.load(from: file), AppSettings())
    }

    func testPartialSettingsKeepWhatTheyHave() throws {
        let folder = temporaryFolder(self)
        let file = folder.appendingPathComponent("settings.json")
        try #"{"model": "gatita-7.1-mini"}"#.write(to: file, atomically: true, encoding: .utf8)
        let partial = SettingsStore.load(from: file)
        XCTAssertEqual(partial.model, "gatita-7.1-mini")
        XCTAssertEqual(partial.projectRoot, "")
    }

    func testFirstLaunchCopiesTheOldDefaultsAcross() throws {
        let folder = temporaryFolder(self)
        let oldDefaults = UserDefaults(suiteName: "gatita-tests-\(UUID().uuidString)")!
        oldDefaults.set("~/Old", forKey: "projectRoot")
        oldDefaults.set(["web"], forKey: "connectors")
        let migrated = SettingsStore.loadOrMigrate(file: folder.appendingPathComponent("first.json"), defaults: oldDefaults)
        XCTAssertEqual(migrated.projectRoot, "~/Old")
        XCTAssertEqual(migrated.connectors, ["web"])
    }

    func testKeepAwakeIsOffByDefaultAndSaved() throws {
        XCTAssertFalse(AppSettings().keepAwake)
        var settings = AppSettings()
        settings.keepAwake = true
        let loaded = try JSONDecoder().decode(AppSettings.self, from: try JSONEncoder().encode(settings))
        XCTAssertTrue(loaded.keepAwake)
    }

    // MARK: - Chat history

    func testTitlesAndPreviewsComeFromTheMessages() {
        let sample = [
            ChatMessage(role: "user", content: "Can u create a quick python script to sort files"),
            ChatMessage(role: "assistant", content: "Sure.\nHere is the script."),
        ]
        XCTAssertEqual(ChatHistory.title(for: sample), "Can u create a quick python script to sort files")
        XCTAssertLessThanOrEqual(ChatHistory.title(for: [ChatMessage(role: "user", content: String(repeating: "word ", count: 30))]).count, 49)
        XCTAssertEqual(ChatHistory.title(for: []), "New chat")
        XCTAssertEqual(ChatHistory.preview(for: sample), "Sure.")
    }

    func testSavedChatsLoadBack() {
        let folder = temporaryFolder(self)
        let file = folder.appendingPathComponent("chats.json")
        let sample = [ChatMessage(role: "user", content: "hi"), ChatMessage(role: "assistant", content: "hello")]
        let chat = Conversation(id: UUID(), updatedAt: Date(timeIntervalSince1970: 1000), messages: sample)
        ChatHistory.save([chat], to: file)
        XCTAssertEqual(ChatHistory.load(from: file), [chat])
        XCTAssertTrue(ChatHistory.load(from: folder.appendingPathComponent("none.json")).isEmpty)
    }

    func testChatTitlesAreCleanedAndASavedTitleIsShown() {
        XCTAssertEqual(ChatHistory.cleanTitle("\"Fix the sidebar title.\""), "Fix the sidebar title")
        XCTAssertEqual(ChatHistory.cleanTitle("Title: Sort Python files\n"), "Sort Python files")
        XCTAssertNil(ChatHistory.cleanTitle("   \n "))
        XCTAssertLessThanOrEqual((ChatHistory.cleanTitle(String(repeating: "word ", count: 40)) ?? "").count, 60)

        let sample = [ChatMessage(role: "user", content: "Can u create a quick python script to sort files")]
        let prompt = ChatHistory.titlePrompt(messages: sample)
        XCTAssertTrue(prompt.contains("2 to 5 words"))
        XCTAssertTrue(prompt.contains("Can u create a quick python script"))

        var titled = Conversation(id: UUID(), updatedAt: Date(), messages: sample)
        titled.customTitle = "Sort files with Python"
        XCTAssertEqual(titled.title, "Sort files with Python")
    }

    // MARK: - Logs, reports, and analytics

    func testLogsReportsAndAnalyticsStayOnTheMac() throws {
        let logDir = temporaryFolder(self, name: "gatita-logs")
        let logs = AppLog(directory: logDir)
        logs.info("hello log")
        let logText = try String(contentsOf: logDir.appendingPathComponent("gatita.log"), encoding: .utf8)
        XCTAssertTrue(logText.contains("[INFO] hello log"), logText)

        let reportName = logs.recordFailure(kind: "reply", message: "HTTP 403", details: ["model: gatita-7.1-max"])
        XCTAssertTrue(reportName?.hasPrefix("failures/") == true)
        let reportText = reportName.flatMap { try? String(contentsOf: logDir.appendingPathComponent($0), encoding: .utf8) } ?? ""
        XCTAssertTrue(reportText.contains("HTTP 403"))

        let stats = Analytics(file: logDir.appendingPathComponent("analytics.json"))
        stats.count("tool_error")
        stats.count("tool_error")
        XCTAssertEqual(Analytics(file: stats.file).summary()["tool_error"], 2)
    }

    func testReportsCanBeListedAndReadButNotOtherFiles() throws {
        let root = try makeProjectFixture(self)
        let logDir = temporaryFolder(self, name: "gatita-logs")
        let logs = AppLog(directory: logDir)
        logs.info("hello log")
        let reportName = logs.recordFailure(kind: "reply", message: "HTTP 403", details: [])
        let reader = ProjectTools(root: root, allowWrites: false, logDirectory: logDir)

        XCTAssertTrue(reader.run(name: "list_reports", arguments: "{}").contains("failures/"))
        XCTAssertTrue(reader.run(name: "read_report", arguments: #"{"name": "\#(reportName ?? "")"}"#).contains("HTTP 403"))
        XCTAssertTrue(reader.run(name: "read_report", arguments: #"{"name": "gatita.log"}"#).contains("hello log"))
        XCTAssertTrue(reader.run(name: "read_report", arguments: #"{"name": "../../etc/hosts"}"#).hasPrefix("error:"))
    }
}

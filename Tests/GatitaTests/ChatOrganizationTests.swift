//
//  ChatOrganizationTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// Pinned chats and folders in the sidebar.
final class ChatOrganizationTests: XCTestCase {
    private func chat(_ title: String, at seconds: TimeInterval, pinned: Bool? = nil, folder: String? = nil) -> Conversation {
        var chat = Conversation(id: UUID(), updatedAt: Date(timeIntervalSince1970: seconds),
                                messages: [ChatMessage(role: "user", content: title)])
        chat.pinned = pinned
        chat.folder = folder
        return chat
    }

    func testChatsSavedBeforePinsAndFoldersStillLoad() throws {
        let old = #"[{"id": "8E4A2B1C-0000-4000-8000-000000000001", "updatedAt": 0, "messages": []}]"#
        let chats = try JSONDecoder().decode([Conversation].self, from: Data(old.utf8))
        XCTAssertNil(chats.first?.pinned)
        XCTAssertNil(chats.first?.folder)

        let kept = chat("a", at: 1, pinned: true, folder: "Work")
        let again = try JSONDecoder().decode(Conversation.self, from: JSONEncoder().encode(kept))
        XCTAssertEqual(again.pinned, true)
        XCTAssertEqual(again.folder, "Work")
    }

    func testSavingAChatAgainKeepsItsTitlePinAndFolder() {
        var saved = chat("first", at: 1, pinned: true, folder: "Work")
        saved.customTitle = "My title"
        let other = chat("other", at: 2)
        let now = Date(timeIntervalSince1970: 50)
        let messages = [ChatMessage(role: "user", content: "first"), ChatMessage(role: "assistant", content: "hi")]

        let updated = ChatHistory.updated([saved, other], id: saved.id, messages: messages, mode: .chat, at: now)
        let chat = updated.first { $0.id == saved.id }
        XCTAssertEqual(updated.count, 2)
        XCTAssertEqual(chat?.customTitle, "My title")
        XCTAssertEqual(chat?.pinned, true)
        XCTAssertEqual(chat?.folder, "Work")
        XCTAssertEqual(chat?.messages.count, 2)
        XCTAssertEqual(chat?.updatedAt, now)

        let new = UUID()
        let added = ChatHistory.updated([other], id: new, messages: messages, mode: .code, at: now)
        XCTAssertEqual(added.last?.id, new, "a chat saved for the first time is added")
        XCTAssertNil(added.last?.pinned)
    }

    func testTheSidebarShowsPinnedThenFoldersThenTheRest() {
        let chats = [
            chat("old loose", at: 1),
            chat("new loose", at: 9),
            chat("pinned", at: 2, pinned: true),
            chat("pinned in a folder", at: 3, pinned: true, folder: "Work"),
            chat("work", at: 4, folder: "Work"),
            chat("art", at: 5, folder: "Art"),
        ]
        let sections = ChatSidebar.sections(chats, search: "")
        XCTAssertEqual(sections.map(\.title), ["Pinned", "Art", "Work", "Chats"])
        XCTAssertEqual(sections[0].chats.map(\.title), ["pinned in a folder", "pinned"], "newest first")
        XCTAssertEqual(sections[2].chats.map(\.title), ["work"], "a pinned chat shows only under Pinned")
        XCTAssertEqual(sections[3].chats.map(\.title), ["new loose", "old loose"])
        XCTAssertEqual(sections.map(\.kind), [.pinned, .folder, .folder, .rest])
    }

    func testSearchNarrowsEverySectionAndDropsEmptyOnes() {
        let chats = [chat("Swift tips", at: 1, pinned: true), chat("Taxes", at: 2, folder: "Home"), chat("swift build", at: 3)]
        let sections = ChatSidebar.sections(chats, search: "swift")
        XCTAssertEqual(sections.map(\.title), ["Pinned", "Chats"])
        XCTAssertTrue(ChatSidebar.sections([], search: "").isEmpty)
    }

    func testFoldersAreListedOnceInOrder() {
        let chats = [chat("a", at: 1, folder: "Work"), chat("b", at: 2, folder: "art"), chat("c", at: 3, folder: "Work")]
        XCTAssertEqual(ChatSidebar.folders(chats), ["art", "Work"])
    }

    func testFolderNamesAreTrimmedAndABlankNameMeansNoFolder() {
        XCTAssertEqual(ChatSidebar.folderName("  School  "), "School")
        XCTAssertNil(ChatSidebar.folderName("   "))
        XCTAssertEqual(ChatSidebar.folderName(String(repeating: "x", count: 80))?.count, ChatSidebar.maxFolderNameLength)
    }
}

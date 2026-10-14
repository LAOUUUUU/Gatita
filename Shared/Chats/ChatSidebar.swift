//
//  ChatSidebar.swift
//  Gatita
//

import Foundation

/// How the sidebar groups saved chats: pinned ones first, then one section per folder (by name), then the rest.
/// Each section lists its newest chat first. A pinned chat shows only under Pinned, even when it is in a folder.
nonisolated enum ChatSidebar {
    static let maxFolderNameLength = 40

    struct Section: Identifiable, Equatable {
        enum Kind: Equatable {
            case pinned, folder, rest
        }

        let kind: Kind
        let title: String
        let chats: [Conversation]

        var id: String { "\(kind)-\(title)" }
    }

    /// The sections with chats in them, after the search, which looks in titles and messages (`ChatSearch`).
    static func sections(_ chats: [Conversation], search: String) -> [Section] {
        let shown = chats
            .filter { ChatSearch.matches($0, query: search) }
            .sorted { $0.updatedAt > $1.updatedAt }
        let pinned = shown.filter { $0.pinned == true }
        let loose = shown.filter { $0.pinned != true }
        var sections = [Section(kind: .pinned, title: "Pinned", chats: pinned)]
        for folder in folders(loose) {
            sections.append(Section(kind: .folder, title: folder, chats: loose.filter { $0.folder == folder }))
        }
        sections.append(Section(kind: .rest, title: "Chats", chats: loose.filter { $0.folder == nil }))
        return sections.filter { !$0.chats.isEmpty }
    }

    /// Every folder name in use, once each, in alphabetical order whatever the case.
    static func folders(_ chats: [Conversation]) -> [String] {
        Set(chats.compactMap(\.folder)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// A folder name as typed, trimmed and shortened. A blank name means no folder.
    static func folderName(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(maxFolderNameLength))
    }
}

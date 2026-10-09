//
//  FileNode.swift
//  Gatita
//

import Foundation

/// One file or folder in the project, for the file list. Folders carry their children.
nonisolated struct FileNode: Identifiable, Hashable, Sendable {
    /// Path relative to the project root, such as "App/GatitaApp.swift".
    let path: String
    let name: String
    let isDirectory: Bool
    /// nil for files; the folder's contents for folders.
    let children: [FileNode]?

    var id: String { path }
}

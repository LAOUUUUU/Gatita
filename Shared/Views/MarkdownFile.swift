//
//  MarkdownFile.swift
//  Gatita
//

import SwiftUI
import UniformTypeIdentifiers

/// A chat exported as a Markdown file, for the save panel.
struct MarkdownFile: FileDocument {
    static let type = UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText
    static var readableContentTypes: [UTType] { [type] }

    var text: String
    var fileName: String

    init(text: String, fileName: String) {
        self.text = text
        self.fileName = fileName
    }

    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
        fileName = configuration.file.filename ?? "Gatita chat.md"
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

//
//  DroppedFile.swift
//  Gatita
//

import Foundation

/// A file dropped on the prompt box. Its text goes to Gatita with the next message.
struct DroppedFile: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let text: String
    /// Set for a picture. A picture is sent as an image, not as text.
    var image: ChatImage? = nil

    /// The largest text file a drop may bring in. Bigger files are refused rather than read into memory.
    static let maxBytes = 2_000_000
    /// The largest picture. Bigger pictures are refused.
    static let maxImageBytes = 4_000_000
    private static let imageTypes = [
        "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif", "webp": "image/webp",
    ]
    /// A paste at least this long becomes a Markdown attachment instead of text in the box.
    static let pasteThreshold = 2000

    private static let kindNames = ["md": "Markdown"]

    /// What the file is, for its card: "Markdown" for .md, the extension in capitals otherwise, or "Text".
    var kind: String {
        let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
        if ext.isEmpty { return "Text" }
        return Self.kindNames[ext] ?? ext.uppercased()
    }

    /// Long pasted text as "Pasted text.md", then "Pasted text 2.md", and so on.
    static func pasted(_ text: String, among files: [DroppedFile]) -> DroppedFile {
        let existing = files.filter { $0.name.hasPrefix("Pasted text") }.count
        let name = existing == 0 ? "Pasted text.md" : "Pasted text \(existing + 1).md"
        return DroppedFile(name: name, text: text)
    }

    enum ReadError: LocalizedError, Equatable {
        case notAFile(String)
        case tooLarge(String, Int)
        case notText(String)

        var errorDescription: String? {
            switch self {
            case .notAFile(let name):
                return "\(name) is not a file. Drop a file, not a folder."
            case .tooLarge(let name, let limit):
                return "\(name) is larger than \(limit / 1_000_000) MB, so Gatita cannot read it."
            case .notText(let name):
                return "\(name) is not a text file or a PNG, JPEG, GIF, or WebP picture, so Gatita cannot read it."
            }
        }
    }

    /// Reads a dropped file: a text file as UTF-8, or a PNG, JPEG, GIF, or WebP picture. Says why it cannot.
    static func read(_ url: URL) throws -> DroppedFile {
        // Files chosen in a picker need their access opened first. Other URLs are not affected.
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw ReadError.notAFile(url.lastPathComponent) }
        let name = url.lastPathComponent
        let size = values.fileSize ?? 0

        if let mimeType = imageTypes[url.pathExtension.lowercased()] {
            guard size <= maxImageBytes else { throw ReadError.tooLarge(name, maxImageBytes) }
            let data = try Data(contentsOf: url)
            return DroppedFile(name: name, text: "", image: ChatImage(name: name, mimeType: mimeType, data: data))
        }

        guard size <= maxBytes else { throw ReadError.tooLarge(name, maxBytes) }
        let data = try Data(contentsOf: url)
        // A zero byte means a binary file, even when the rest happens to be valid UTF-8.
        guard !data.contains(0), let text = String(data: data, encoding: .utf8) else { throw ReadError.notText(name) }
        return DroppedFile(name: name, text: text)
    }

    /// The text sent with a message: each text file in order, cut to `limit` characters. Pictures are not text.
    static func context(for files: [DroppedFile], limit: Int) -> String {
        let parts = files.filter { $0.image == nil }.map { "File \($0.name) (attached):\n```\n\($0.text)\n```" }
        return String(parts.joined(separator: "\n\n").prefix(limit))
    }
}

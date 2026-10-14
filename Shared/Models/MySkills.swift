//
//  MySkills.swift
//  Gatita
//

import Foundation

/// Skills you write yourself in Settings: a name and the instructions Gatita follows. They show with "/" like the
/// built-in ones and are kept in Application Support/Gatita/my-skills.json. Their ids start with "my-", so they
/// never take a built-in or plugin skill's place.
nonisolated enum MySkills {
    static var defaultFile: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Gatita/my-skills.json")
    }

    static func load(from file: URL) -> [Skill] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        return (try? JSONDecoder().decode([Skill].self, from: data)) ?? []
    }

    static func save(_ skills: [Skill], to file: URL) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(skills) {
            try? data.write(to: file, options: .atomic)
        }
    }

    /// "my-" and the name in lowercase words joined by dashes, with a number added if that id is taken.
    static func id(for name: String, taken: Set<String>) -> String {
        let words = name.lowercased().split(whereSeparator: { !($0.isLetter || $0.isNumber) })
        let base = "my-" + (words.isEmpty ? "skill" : words.joined(separator: "-"))
        var id = base
        var number = 2
        while taken.contains(id) {
            id = "\(base)-\(number)"
            number += 1
        }
        return id
    }
}

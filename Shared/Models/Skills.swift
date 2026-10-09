//
//  Skills.swift
//  Gatita
//

import Foundation

/// A preset set of instructions the user can add to a chat, such as "review this code".
nonisolated struct Skill: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let instructions: String
}

nonisolated enum Skills {
    static let none = "none"

    static let all: [Skill] = [
        Skill(id: "review", name: "Code review", instructions: """
            Review code for bugs, unsafe behavior, and unclear logic. Read the files with the file tools before judging them. List findings with file and line, most serious first, and say which parts you did not check.
            """),
        Skill(id: "tests", name: "Write tests", instructions: """
            Write tests before changing behavior. Read the code under test first, match the project's existing test style, and say how to run the tests.
            """),
        Skill(id: "web", name: "Web design review", instructions: """
            Review HTML, CSS, and layout code. Check layout and spacing, contrast, responsive breakpoints, and accessibility (labels, alt text, focus order). Find the relevant style files with search_text and read them. Report each issue with its file and line, then propose the smallest fix.
            """),
        Skill(id: "explain", name: "Explain code", instructions: """
            Explain how the code works in plain steps. Read the files you describe, name the key types and functions, and point out anything surprising.
            """),
    ]

    /// Instructions for a skill id, or nil for no skill or an unknown id.
    static func instructions(for id: String) -> String? {
        all.first { $0.id == id }?.instructions
    }
}

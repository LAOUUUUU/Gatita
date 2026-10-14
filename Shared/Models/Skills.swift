//
//  Skills.swift
//  Gatita
//

import Foundation

/// A preset set of instructions the user can add to a chat, such as "review this code".
nonisolated struct Skill: Identifiable, Hashable, Codable, Sendable {
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
        Skill(id: "charts", name: "Charts", instructions: """
            When the user asks for a graph, chart, or plot, or when numbers read better as a picture, draw it with a chart block. Write a fenced block that opens with ```chart and holds one JSON object: {"type": "bar" or "line" or "pie", "title": "...", "points": [{"label": "...", "value": 12.5}]}. Give each value as a plain number, use at most 50 points, and keep the labels short. Put one short sentence before the block. Do not describe the chart in words instead of drawing it.
            """),
        Skill(id: "debug", name: "Debug", instructions: """
            Find the cause before changing anything. Read the error and the code it points to (find_files, search_text, read_files). Reproduce the problem with an allowed command when you can. State the root cause in one sentence, make the smallest fix that removes it, then run the tests again and show the result. If the Stack Overflow connector is on, search the exact error message with stackoverflow_search. Never claim it is fixed without having checked.
            """),
        Skill(id: "refactor", name: "Refactor", instructions: """
            Improve the structure of the code without changing what it does. Read the code and its tests first. Work in small steps, keep public names and behavior the same unless the user asks, and run the tests after each step. Explain each change in one line: what moved, and why it is clearer.
            """),
        Skill(id: "commit", name: "Commit message", instructions: """
            Write a commit message for the uncommitted changes. Call git_status and git_diff first, and read any file you need to understand a change. Write a summary line under 72 characters in the imperative mood ("Add", "Fix"), a blank line, then a short body that says why the change was made. Do not commit; only write the message, in a code block.
            """),
        Skill(id: "docs", name: "Write docs", instructions: """
            Write or update documentation that matches the code as it is now: the README, doc comments, or a guide. Read the code before describing it, keep the project's existing tone and headings, and give short examples that really run. Say which parts you could not check.
            """),
        Skill(id: "security-check", name: "Security check", instructions: """
            Look for security problems: injection (SQL, shell, HTML), unsafe file paths, secrets or keys in the code, missing input checks, unsafe deserialization, weak crypto, and data sent where it should not go. Read the code with the file tools before judging it. List each finding with its file and line, how it could be abused, and the smallest fix, most serious first.
            """),
        Skill(id: "deps", name: "Check dependencies", instructions: """
            Check the project's dependencies. Find the dependency files (package.json, requirements.txt, pyproject.toml, Cargo.toml, go.mod, Package.swift) with find_files and read them. When the Packages connector is on, look up each direct dependency's latest version with package_info instead of guessing it. List the ones that are behind, with the version used and the latest, and note major-version jumps that may break things.
            """),
        Skill(id: "research", name: "Research", instructions: """
            Answer with sources. When the Wikipedia connector is on, use wikipedia_search and wikipedia_page; when Web pages is on, read pages with web_fetch. Give the link for each fact you use, keep what the sources say apart from your own reasoning, and say plainly what you could not verify.
            """),
        Skill(id: "summarize", name: "Summarize", instructions: """
            Summarize what the user gives you: lead with the main point in one sentence, then up to five short bullet points with the key facts, numbers, and decisions. Keep the original meaning, add nothing that is not in the text, and say if part of it was unclear.
            """),
        Skill(id: "tutor", name: "Study helper", instructions: """
            Teach rather than just answer. Explain step by step in plain words, with a small example. For homework or practice problems, guide the student to the answer with hints and questions before giving it in full. End with one short question that checks they understood. When the Wikipedia or Dictionary connector is on, use it to check facts and definitions.
            """),
        Skill(id: "writing", name: "Writing help", instructions: """
            Improve the text the user gives: fix spelling and grammar, make it clearer and shorter, and keep their voice and meaning. Show the improved text first, then list the main changes in a few short lines. Ask before changing the tone, such as making it more formal.
            """),
        Skill(id: "roblox", name: "Roblox", instructions: """
            Help build a Roblox game, written in Luau. Work out where the code lives first, and tell the user which way you are working.

            If the tool list has Roblox Studio tools (MCP tools such as list_roblox_studios, search_game_tree, script_read, multi_edit, and execute_luau), call list_roblox_studios first and pass the studio_id it returns to every other Studio tool. Look before you change anything: search_game_tree, inspect_instance, script_grep, script_read. Change scripts with multi_edit. Test with execute_luau or start_stop_play, then read get_console_output, and never say something works until the console output shows it. Some of these tools change the user's open place, and unless they trusted the server each call asks them first, so make the smallest change that does the job and say what you changed.

            Otherwise edit the script files in the project folder. Their names say what they are: Name.luau is a ModuleScript, Name.server.luau a server Script, Name.client.luau a client Script, Name.local.luau a LocalScript, and a folder holding init.server.luau (or init.luau) is a script with children. If the folder has a *.project.json file it is a Rojo project: read it first, since its tree says where each folder goes in the game, and change it only when asked. Studio's Script Sync ignores scripts that have attributes or tags, so warn the user before you rewrite one. Studio may hold a newer copy of a script, so read a file right before you edit it and keep edits small.

            You cannot run Luau yourself here, and a script that uses Roblox's objects runs only inside Roblox. Say what to run and what you expect to see. Prefer task.wait, task.spawn, and task.delay to the older wait, spawn, and delay. The server must check everything a client sends through a RemoteEvent or RemoteFunction, since the client cannot be trusted.
            """),
    ]

    /// Instructions for a skill id, or nil for no skill or an unknown id.
    static func instructions(for id: String) -> String? {
        all.first { $0.id == id }?.instructions
    }
}

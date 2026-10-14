//
//  SyntaxHighlighter.swift
//  Gatita
//

import Foundation

/// Colors for code blocks without a library: a small tokenizer that knows the comments, strings, and keywords of
/// the languages replies use most. It is not a parser; anything it doesn't know stays plain text.
nonisolated enum SyntaxHighlighter {
    enum Kind: Equatable, Sendable {
        case keyword, type, string, number, comment, plain
    }

    struct Token: Equatable, Sendable {
        let text: String
        let kind: Kind
    }

    /// How one family of languages writes comments, strings, and keywords.
    private struct Rules {
        var lineComments: [String] = ["//"]
        var blockComments: [(open: String, close: String)] = [("/*", "*/")]
        var quotes: Set<Character> = ["\"", "'"]
        var tripleQuotes = false
        var keywords: Set<String> = []
        /// Capitalized names are types in languages that name types that way.
        var capitalizedTypes = false
        /// Lua's long brackets: `[[ … ]]` and `[=[ … ]=]` (the same number of = at both ends) are strings, and after
        /// `--` they are comments.
        var longBrackets = false
        /// Words that are keywords only in some places (Luau's `type`, `export`, `continue`, `const`). A call such as
        /// `type(x)` and a field such as `item.type` are plain names.
        var contextualKeywords: Set<String> = []
    }

    private static let cLike: Set<String> = [
        "if", "else", "for", "while", "do", "switch", "case", "default", "break", "continue", "return", "goto",
        "struct", "enum", "union", "typedef", "const", "static", "void", "int", "char", "float", "double", "long",
        "short", "unsigned", "signed", "bool", "true", "false", "null", "nullptr", "class", "public", "private",
        "protected", "new", "delete", "this", "virtual", "override", "namespace", "using", "template", "typename",
        "import", "package", "extends", "implements", "interface", "final", "abstract", "throws", "throw", "try",
        "catch", "finally", "fun", "val", "var", "when", "is", "in", "object", "func", "go", "defer", "chan", "map",
        "range", "type", "fn", "let", "mut", "impl", "trait", "pub", "use", "mod", "match", "self", "Self", "crate",
        "async", "await", "move", "where", "loop", "as", "sizeof", "include", "define", "string", "byte", "rune",
        "nil", "super", "instanceof", "synchronized", "volatile", "extern", "inline", "auto", "operator",
    ]

    /// Lua 5.1's reserved words, which Luau keeps.
    private static let lua: Set<String> = [
        "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in", "local", "nil", "not",
        "or", "repeat", "return", "then", "true", "until", "while",
    ]

    private static func rules(for language: String) -> Rules? {
        switch language.lowercased() {
        case "swift":
            return Rules(keywords: ["let", "var", "func", "if", "else", "guard", "return", "struct", "class", "enum",
                                    "protocol", "extension", "import", "for", "in", "while", "repeat", "switch", "case",
                                    "default", "break", "continue", "where", "try", "catch", "throw", "throws", "async",
                                    "await", "self", "Self", "nil", "true", "false", "static", "private", "public",
                                    "internal", "fileprivate", "open", "init", "deinit", "some", "any", "inout", "defer",
                                    "do", "as", "is", "final", "lazy", "weak", "unowned", "override", "mutating",
                                    "nonisolated", "actor", "typealias", "associatedtype", "subscript", "get", "set",
                                    "willSet", "didSet", "rethrows", "super", "fallthrough", "convenience", "required",
                                    "indirect", "consuming", "borrowing", "sending"],
                         capitalizedTypes: true)
        case "python", "py":
            return Rules(lineComments: ["#"], blockComments: [], tripleQuotes: true,
                         keywords: ["def", "class", "import", "from", "as", "if", "elif", "else", "for", "while", "return",
                                    "yield", "with", "try", "except", "finally", "raise", "pass", "break", "continue",
                                    "lambda", "None", "True", "False", "and", "or", "not", "in", "is", "global",
                                    "nonlocal", "async", "await", "self", "del", "assert", "match", "case"])
        case "javascript", "js", "jsx", "typescript", "ts", "tsx", "mjs", "cjs":
            return Rules(quotes: ["\"", "'", "`"],
                         keywords: ["const", "let", "var", "function", "return", "if", "else", "for", "while", "do",
                                    "switch", "case", "default", "break", "continue", "new", "class", "extends",
                                    "import", "export", "from", "as", "async", "await", "try", "catch", "finally",
                                    "throw", "typeof", "instanceof", "in", "of", "null", "undefined", "true", "false",
                                    "this", "super", "interface", "type", "enum", "implements", "public", "private",
                                    "protected", "readonly", "static", "void", "yield", "delete", "keyof", "declare"],
                         capitalizedTypes: true)
        case "json", "jsonc":
            return Rules(lineComments: [], blockComments: [], quotes: ["\""], keywords: ["true", "false", "null"])
        case "sh", "bash", "zsh", "shell", "console", "fish":
            return Rules(lineComments: ["#"], blockComments: [],
                         keywords: ["if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done", "case",
                                    "esac", "function", "return", "export", "local", "in", "echo", "cd", "set", "unset",
                                    "source", "exit", "sudo"])
        case "ruby", "rb":
            return Rules(lineComments: ["#"], blockComments: [],
                         keywords: ["def", "end", "class", "module", "if", "elsif", "else", "unless", "while", "until",
                                    "for", "in", "do", "return", "yield", "nil", "true", "false", "self", "require",
                                    "begin", "rescue", "ensure", "case", "when", "then", "and", "or", "not"],
                         capitalizedTypes: true)
        case "yaml", "yml", "toml", "ini", "dockerfile", "makefile", "r":
            return Rules(lineComments: ["#"], blockComments: [], keywords: ["true", "false", "null", "yes", "no"])
        case "css", "scss", "less":
            return Rules(lineComments: language.lowercased() == "css" ? [] : ["//"],
                         keywords: ["important", "media", "import", "from", "to"])
        case "html", "xml", "svg", "plist", "vue":
            return Rules(lineComments: [], blockComments: [("<!--", "-->")], quotes: ["\""])
        case "sql":
            return Rules(lineComments: ["--"],
                         keywords: Set(["select", "from", "where", "insert", "into", "values", "update", "set",
                                        "delete", "create", "table", "drop", "alter", "join", "left", "right", "inner",
                                        "outer", "on", "group", "by", "order", "having", "limit", "and", "or", "not",
                                        "null", "as", "distinct", "primary", "key", "index"].flatMap { [$0, $0.uppercased()] }))
        case "lua", "luau":
            return Rules(lineComments: ["--"], blockComments: [], quotes: ["\"", "'", "`"], keywords: lua,
                         longBrackets: true, contextualKeywords: ["type", "export", "continue", "const"])
        case "c", "h", "cpp", "c++", "cc", "hpp", "objc", "objective-c", "java", "kotlin", "kt", "go", "golang",
             "rust", "rs", "cs", "csharp", "c#", "dart", "scala", "php":
            return Rules(keywords: cLike, capitalizedTypes: true)
        case "":
            return nil
        default:
            return nil
        }
    }

    /// Fences that hold words or output rather than code. Their apostrophes and addresses would read as strings
    /// and comments, so they stay plain, as GitHub shows them.
    private static let plainLanguages: Set<String> = ["", "text", "txt", "plaintext", "plain", "output", "log", "md",
                                                      "markdown", "diff"]

    /// The tokens of a block, in order. Joined, their texts give the block back exactly.
    static func tokens(_ code: String, language: String) -> [Token] {
        if plainLanguages.contains(language.lowercased()) {
            return code.isEmpty ? [] : [Token(text: code, kind: .plain)]
        }
        // Other languages it does not know still get strings, numbers, and // and /* */ comments, which most share.
        let rules = rules(for: language) ?? Rules()
        let characters = Array(code)
        var tokens: [Token] = []
        var plain = ""
        func flush() {
            if !plain.isEmpty { tokens.append(Token(text: plain, kind: .plain)); plain = "" }
        }
        func emit(_ range: Range<Int>, _ kind: Kind) {
            flush()
            tokens.append(Token(text: String(characters[range]), kind: kind))
        }
        // Markers are made into arrays once and compared in place; making arrays at every character was most of
        // the time spent.
        let isSwift = language.lowercased() == "swift"
        let lineComments = rules.lineComments.map(Array.init)
        let blockComments = rules.blockComments.map { (open: Array($0.open), close: Array($0.close)) }
        func starts(_ needle: [Character], at index: Int) -> Bool {
            var position = index
            for character in needle {
                guard position < characters.count, characters[position] == character else { return false }
                position += 1
            }
            return true
        }
        func isWordCharacter(_ character: Character) -> Bool {
            character.isLetter || character.isNumber || character == "_" || character == "$"
        }
        /// The level of a long bracket that opens at `index` (`[[` is 0, `[=[` is 1), or nil when none does.
        func longBracketLevel(at index: Int) -> Int? {
            guard index < characters.count, characters[index] == "[" else { return nil }
            var position = index + 1
            while position < characters.count, characters[position] == "=" { position += 1 }
            return position < characters.count && characters[position] == "[" ? position - index - 1 : nil
        }
        /// Where the long bracket of `level` that opens at `index` ends: after its closing bracket, which has the same
        /// number of =, or at the end of the code when it is never closed.
        func longBracketEnd(opening index: Int, level: Int) -> Int {
            var position = index + level + 2
            while position < characters.count {
                if characters[position] == "]" {
                    var equals = 0
                    while position + 1 + equals < characters.count, characters[position + 1 + equals] == "=" { equals += 1 }
                    if equals == level, position + 1 + equals < characters.count, characters[position + 1 + equals] == "]" {
                        return position + level + 2
                    }
                }
                position += 1
            }
            return characters.count
        }
        let dashes: [Character] = ["-", "-"]
        /// Whether a word of `rules.contextualKeywords` at `start..<end` is used as a keyword: not after a `.` or `:`
        /// (a field or method) and not before a `(` (a call).
        func isContextualKeyword(_ word: String, from start: Int, to end: Int) -> Bool {
            guard rules.contextualKeywords.contains(word) else { return false }
            if start > 0, characters[start - 1] == "." || characters[start - 1] == ":" { return false }
            var next = end
            while next < characters.count, characters[next] == " " || characters[next] == "\t" { next += 1 }
            return next >= characters.count || characters[next] != "("
        }

        var index = 0
        scan: while index < characters.count {
            let character = characters[index]
            if rules.longBrackets {
                if starts(dashes, at: index), let level = longBracketLevel(at: index + 2) {
                    let end = longBracketEnd(opening: index + 2, level: level)
                    emit(index..<end, .comment)
                    index = end
                    continue scan
                }
                if let level = longBracketLevel(at: index) {
                    let end = longBracketEnd(opening: index, level: level)
                    emit(index..<end, .string)
                    index = end
                    continue scan
                }
            }
            for marker in lineComments where starts(marker, at: index) {
                var end = index
                while end < characters.count, characters[end] != "\n" { end += 1 }
                emit(index..<end, .comment)
                index = end
                continue scan
            }
            for block in blockComments where starts(block.open, at: index) {
                var end = index + block.open.count
                while end < characters.count, !starts(block.close, at: end) { end += 1 }
                end = min(characters.count, end + block.close.count)
                emit(index..<end, .comment)
                index = end
                continue scan
            }
            if rules.quotes.contains(character) {
                let triple = [character, character, character]
                if rules.tripleQuotes || isSwift, starts(triple, at: index) {
                    var end = index + 3
                    while end < characters.count, !starts(triple, at: end) { end += 1 }
                    end = min(characters.count, end + 3)
                    emit(index..<end, .string)
                    index = end
                    continue
                }
                var end = index + 1
                var escaped = false
                while end < characters.count {
                    let next = characters[end]
                    if escaped { escaped = false } else if next == "\\" { escaped = true } else if next == character { end += 1; break } else if next == "\n" && character != "`" { break }
                    end += 1
                }
                emit(index..<min(end, characters.count), .string)
                index = min(end, characters.count)
                continue
            }
            let previous: Character? = index > 0 ? characters[index - 1] : nil
            if character.isNumber, previous.map({ !isWordCharacter($0) }) ?? true {
                var end = index + 1
                while end < characters.count, characters[end].isHexDigit || "xXoObB._".contains(characters[end]) { end += 1 }
                emit(index..<end, .number)
                index = end
                continue
            }
            if character.isLetter || character == "_" || character == "@" || character == "#" && rules.lineComments.contains("#") == false {
                var end = index + 1
                while end < characters.count, isWordCharacter(characters[end]) { end += 1 }
                let word = String(characters[index..<end])
                let bare = word.hasPrefix("@") || word.hasPrefix("#") ? String(word.dropFirst()) : word
                if rules.keywords.contains(word) || (word != bare && !bare.isEmpty && isSwift)
                    || (!rules.contextualKeywords.isEmpty && isContextualKeyword(word, from: index, to: end)) {
                    emit(index..<end, .keyword)
                } else if rules.capitalizedTypes, bare.first?.isUppercase == true {
                    emit(index..<end, .type)
                } else {
                    flush()
                    tokens.append(Token(text: word, kind: .plain))
                }
                index = end
                continue
            }
            plain.append(character)
            index += 1
        }
        flush()
        return tokens
    }

    /// The name shown on a code block, such as "TypeScript" for "ts". Unknown names are shown as written.
    static func displayName(_ language: String) -> String {
        let names = ["swift": "Swift", "py": "Python", "python": "Python", "js": "JavaScript", "javascript": "JavaScript",
                     "ts": "TypeScript", "typescript": "TypeScript", "tsx": "TSX", "jsx": "JSX", "json": "JSON",
                     "sh": "Shell", "bash": "Bash", "zsh": "zsh", "shell": "Shell", "console": "Terminal",
                     "html": "HTML", "css": "CSS", "scss": "SCSS", "xml": "XML", "yaml": "YAML", "yml": "YAML",
                     "md": "Markdown", "markdown": "Markdown", "sql": "SQL", "c": "C", "cpp": "C++", "c++": "C++",
                     "java": "Java", "kotlin": "Kotlin", "kt": "Kotlin", "go": "Go", "rust": "Rust", "rs": "Rust",
                     "rb": "Ruby", "ruby": "Ruby", "cs": "C#", "csharp": "C#", "php": "PHP", "toml": "TOML",
                     "diff": "Diff", "text": "Text", "txt": "Text", "lua": "Lua", "luau": "Luau", "dart": "Dart", "r": "R"]
        let key = language.lowercased()
        if key.isEmpty { return "Code" }
        return names[key] ?? language
    }
}

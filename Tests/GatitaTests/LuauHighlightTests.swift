//
//  LuauHighlightTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// Lua and Luau code blocks, which Roblox scripts are written in: `--` comments, long brackets, the language's
/// own keywords, and `//` as an operator rather than a comment.
final class LuauHighlightTests: XCTestCase {
    private func tokens(_ code: String, _ language: String = "luau") -> [SyntaxHighlighter.Token] {
        SyntaxHighlighter.tokens(code, language: language)
    }

    /// The text of every token of one kind, in order.
    private func texts(_ kind: SyntaxHighlighter.Kind, in code: String, _ language: String = "luau") -> [String] {
        tokens(code, language).filter { $0.kind == kind }.map(\.text)
    }

    func testTwoDashesStartALineComment() {
        XCTAssertEqual(texts(.comment, in: "local x = 1 -- note\nprint(x)"), ["-- note"])
    }

    func testLongBracketsMakeABlockComment() {
        // The closing bracket needs the same number of = as the opening one, so "]]" does not end a level-2 comment.
        let code = "--[[ first\nsecond ]] local x = 1\n--[==[ a ]] still inside\n]==] local y = 2"
        XCTAssertEqual(texts(.comment, in: code), ["--[[ first\nsecond ]]", "--[==[ a ]] still inside\n]==]"])
    }

    func testDashesFollowedByAnythingButALongBracketMakeALineComment() {
        XCTAssertEqual(texts(.comment, in: "--[ not long\nprint(1)"), ["--[ not long"])
        XCTAssertEqual(texts(.comment, in: "--[=x\nprint(1)"), ["--[=x"])
        XCTAssertEqual(texts(.comment, in: "---- docs\nprint(1)"), ["---- docs"])
    }

    func testAnUnclosedLongCommentRunsToTheEnd() {
        let code = "print(1)\n--[[ never closed\nprint(2)"
        XCTAssertEqual(texts(.comment, in: code), ["--[[ never closed\nprint(2)"])
        XCTAssertEqual(tokens(code).map(\.text).joined(), code)
    }

    func testLongBracketsMakeALongString() {
        // Like comments, a level-2 string is not ended by "]]", and a long string has no escapes.
        let code = "local a = [[line one\nline two]]\nlocal b = [==[ has ]] inside \\]==] ]==]"
        XCTAssertEqual(texts(.string, in: code), ["[[line one\nline two]]", "[==[ has ]] inside \\]==]"])
    }

    func testIndexingIsNotALongString() {
        XCTAssertEqual(texts(.string, in: "local v = items[i] + grid[row][col]"), [])
    }

    func testEveryLuaReservedWordIsAKeyword() {
        let reserved = ["and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in", "local",
                        "nil", "not", "or", "repeat", "return", "then", "true", "until", "while"]
        for word in reserved {
            XCTAssertEqual(tokens(word).map(\.kind), [.keyword], word)
        }
        XCTAssertEqual(texts(.keyword, in: "local endpoint = format(notify)"), ["local"], "only whole words count")
    }

    func testTypeExportContinueAndConstAreKeywordsOnlyWhereTheyAreUsedAsKeywords() {
        XCTAssertEqual(texts(.keyword, in: "export type Point = { x: number }"), ["export", "type"])
        XCTAssertEqual(texts(.keyword, in: "for _, v in items do\n  if v then continue end\nend"),
                       ["for", "in", "do", "if", "then", "continue", "end", "end"])
        XCTAssertEqual(texts(.keyword, in: "const limit = 10"), ["const"])
        // The same words used as names: a call, and a field.
        XCTAssertEqual(texts(.keyword, in: "if type(value) == \"string\" then end"), ["if", "then", "end"])
        XCTAssertEqual(texts(.keyword, in: "local kind = item.type"), ["local"])
        XCTAssertEqual(texts(.keyword, in: "continue()"), [])
    }

    func testQuotedStringsAndInterpolatedBackticksAreStrings() {
        // A "--" inside a string is not a comment, and a backtick string (Luau's interpolation) is one string.
        let code = "print(\"a -- not a comment\", 'it\\'s', `Hello {name}!`)"
        XCTAssertEqual(texts(.string, in: code), ["\"a -- not a comment\"", "'it\\'s'", "`Hello {name}!`"])
        XCTAssertEqual(texts(.comment, in: code), [])
    }

    func testARealScriptKeepsItsTextAndIsColoredSensibly() {
        let code = """
        --!strict
        local Players = game:GetService("Players")
        local MAX_HEALTH = 0xFF + 0b101 + 1_000 + 3.14 + 1e5
        --[[ Heals every player
        once a second. ]]
        export type Settings = { rate: number }
        local function heal(player: Player, amount: number): boolean
            local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
            if not humanoid then
                return false
            end
            humanoid.Health += amount // 1
            print(`Healed {player.Name} by {amount}`)
            return true
        end
        for _, player in Players:GetPlayers() do
            task.spawn(heal, player, 10)
        end
        """
        XCTAssertEqual(tokens(code).map(\.text).joined(), code, "joined, the tokens give the script back exactly")
        XCTAssertEqual(texts(.comment, in: code), ["--!strict", "--[[ Heals every player\nonce a second. ]]"])
        XCTAssertEqual(texts(.string, in: code), ["\"Players\"", "\"Humanoid\"", "`Healed {player.Name} by {amount}`"])
        XCTAssertEqual(texts(.number, in: code), ["0xFF", "0b101", "1_000", "3.14", "1e5", "1", "10"])
        XCTAssertTrue(texts(.keyword, in: code).contains("export"))
        // Roblox names are PascalCase everywhere (Players, GetService, Character), so capitalized words are not types here.
        XCTAssertEqual(texts(.type, in: code), [])
    }

    func testLuaAndLuauAreOneLanguageAndTheBlockIsLabeled() {
        XCTAssertEqual(SyntaxHighlighter.displayName("luau"), "Luau")
        XCTAssertEqual(SyntaxHighlighter.displayName("lua"), "Lua")
        let code = "local x = 1 -- one\nreturn x // 2"
        XCTAssertEqual(tokens(code, "lua"), tokens(code, "luau"))
        XCTAssertEqual(tokens(code, "LUAU"), tokens(code, "luau"), "the language name is not case sensitive")
    }

    func testFloorDivisionIsNotAComment() {
        // `//` is an operator in Luau (a // b is math.floor(a / b)). Lua blocks used to be colored like C, where it starts a comment.
        for language in ["luau", "lua"] {
            XCTAssertEqual(texts(.comment, in: "local half = total // 2\nprint(half)", language), [], language)
        }
    }
}

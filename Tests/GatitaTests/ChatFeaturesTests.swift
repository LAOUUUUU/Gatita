//
//  ChatFeaturesTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// Regenerate and edit, the code highlighter, reading aloud, exporting a chat, and your own skills.
final class ChatFeaturesTests: XCTestCase {
    private let question = ChatMessage(role: "user", content: "first", attachedContext: "File a.swift (attached):\n```\nA\n```", images: nil)
    private let answer = ChatMessage(role: "assistant", content: "one")
    private let second = ChatMessage(role: "user", content: "second")
    private let secondAnswer = ChatMessage(role: "assistant", content: "two")
    private var chat: [ChatMessage] { [question, answer, second, secondAnswer] }

    // MARK: - Regenerate and edit

    func testRegeneratingAReplySendsItsQuestionAgainAndDropsWhatCameAfter() throws {
        let result = try XCTUnwrap(MessageActions.regenerate(chat, replyID: answer.id))
        XCTAssertEqual(result.kept, [])
        XCTAssertEqual(result.question, question)

        let last = try XCTUnwrap(MessageActions.regenerate(chat, replyID: secondAnswer.id))
        XCTAssertEqual(last.kept.map(\.id), [question.id, answer.id])
        XCTAssertEqual(last.question.id, second.id)
    }

    func testAReplyWithNoQuestionBeforeItCannotBeRegenerated() {
        XCTAssertNil(MessageActions.regenerate([answer], replyID: answer.id))
        XCTAssertNil(MessageActions.regenerate(chat, replyID: UUID()))
    }

    func testEditingAQuestionKeepsItsAttachmentsAndDropsEverythingAfterIt() throws {
        let result = try XCTUnwrap(MessageActions.edit(chat, questionID: question.id, newText: "  first, but better "))
        XCTAssertEqual(result.kept, [])
        XCTAssertEqual(result.question.content, "first, but better")
        XCTAssertEqual(result.question.attachedContext, "File a.swift (attached):\n```\nA\n```")
        XCTAssertNotEqual(result.question.id, question.id, "the edited question is a new message")
        XCTAssertNil(MessageActions.edit(chat, questionID: question.id, newText: "   "), "an empty edit is not sent")
        XCTAssertNil(MessageActions.edit(chat, questionID: answer.id, newText: "x"), "only questions can be edited")
    }

    func testAnEditedQuestionReadsItsMentionsAgainAndKeepsAttachedFiles() throws {
        let old = ChatMessage(role: "user", content: "explain @App/a.swift",
                              attachedContext: "File App/a.swift:\n```\nlet a = 1\n```\n\nFile notes.txt (attached):\n```\nN\n```")
        let plan = try XCTUnwrap(MessageActions.edit([old], questionID: old.id, newText: "explain @App/b.swift",
                                                     mentions: "File App/b.swift:\n```\nlet b = 2\n```"))
        XCTAssertEqual(plan.question.attachedContext,
                       "File App/b.swift:\n```\nlet b = 2\n```\n\nFile notes.txt (attached):\n```\nN\n```")
        let plain = try XCTUnwrap(MessageActions.edit([old], questionID: old.id, newText: "just say hi"))
        XCTAssertEqual(plain.question.attachedContext, "File notes.txt (attached):\n```\nN\n```",
                       "the old @App/a.swift is not sent with a question that no longer names it")
    }

    func testTheAttachedFilesPartOfAContextIsFound() {
        XCTAssertEqual(MessageActions.attachedFiles(in: "File a.swift:\n```\nx\n```"), "")
        XCTAssertEqual(MessageActions.attachedFiles(in: "File n.txt (attached):\n```\nN\n```"), "File n.txt (attached):\n```\nN\n```")
        XCTAssertEqual(MessageActions.attachedFiles(in: "Connector Web is on for this message.\n\nFile n.txt (attached):\n```\nN\n```"),
                       "File n.txt (attached):\n```\nN\n```")
    }

    func testTheLastReplyIsTheNewestFinishedAnswer() {
        var streaming = ChatMessage(role: "assistant", content: "half")
        streaming.isStreaming = true
        XCTAssertEqual(MessageActions.lastReply(chat)?.id, secondAnswer.id)
        XCTAssertEqual(MessageActions.lastReply(chat + [ChatMessage(role: "user", content: "x"), streaming])?.id, secondAnswer.id)
        XCTAssertNil(MessageActions.lastReply([question]))
    }

    // MARK: - Code colors

    private func kinds(_ code: String, _ language: String) -> [String: SyntaxHighlighter.Kind] {
        Dictionary(SyntaxHighlighter.tokens(code, language: language).map { ($0.text, $0.kind) }, uniquingKeysWith: { first, _ in first })
    }

    func testSwiftKeywordsTypesStringsNumbersAndComments() {
        let found = kinds("let name: String = \"hi\" // greet\nreturn 42", "swift")
        XCTAssertEqual(found["let"], .keyword)
        XCTAssertEqual(found["String"], .type)
        XCTAssertEqual(found["\"hi\""], .string)
        XCTAssertEqual(found["// greet"], .comment)
        XCTAssertEqual(found["return"], .keyword)
        XCTAssertEqual(found["42"], .number)
    }

    func testPythonUsesHashCommentsAndItsOwnKeywords() {
        let found = kinds("def run(x):  # go\n    return 'ok'", "python")
        XCTAssertEqual(found["def"], .keyword)
        XCTAssertEqual(found["# go"], .comment)
        XCTAssertEqual(found["'ok'"], .string)
    }

    func testAStringWithAnEscapedQuoteStaysOneString() {
        XCTAssertEqual(kinds(#"x = "a \" b" + 1"#, "js")[#""a \" b""#], .string)
    }

    func testAWordInsideAnIdentifierIsNotAKeyword() {
        let found = kinds("letter = iffy", "swift")
        XCTAssertEqual(found["letter"], .plain)
        XCTAssertEqual(found["iffy"], .plain)
    }

    func testTheTokensRebuildTheWholeText() {
        let code = "func f() {\n  /* note */ let s = \"x\"\n}\n"
        XCTAssertEqual(SyntaxHighlighter.tokens(code, language: "swift").map(\.text).joined(), code)
        XCTAssertEqual(SyntaxHighlighter.tokens(code, language: "").map(\.text).joined(), code)
    }

    func testPlainTextAndOutputAreNotColored() {
        for language in ["", "text", "txt", "output", "log", "md"] {
            let tokens = SyntaxHighlighter.tokens("It's at https://example.com, see 2 files", language: language)
            XCTAssertEqual(tokens.map(\.kind), [.plain], "language \(language)")
        }
    }

    func testListeningNeedsAMicrophone() {
        XCTAssertFalse(VoiceInput.canRecord(sampleRate: 0, channels: 0), "a Mac with no microphone reports an empty format")
        XCTAssertTrue(VoiceInput.canRecord(sampleRate: 48_000, channels: 1))
    }

    func testLanguageNamesAreReadForLabels() {
        XCTAssertEqual(SyntaxHighlighter.displayName("ts"), "TypeScript")
        XCTAssertEqual(SyntaxHighlighter.displayName("py"), "Python")
        XCTAssertEqual(SyntaxHighlighter.displayName(""), "Code")
        XCTAssertEqual(SyntaxHighlighter.displayName("zig"), "zig")
    }

    // MARK: - Reading aloud

    func testSpokenTextLeavesOutMarkdownAndCode() {
        let text = SpeechText.plain(from: "# Title\n\nThis is **bold** and `code`, see [the docs](https://x.dev).\n\n```swift\nlet a = 1\n```\n- one\n- two")
        XCTAssertFalse(text.contains("#"), text)
        XCTAssertFalse(text.contains("**"), text)
        XCTAssertFalse(text.contains("let a = 1"), text)
        XCTAssertFalse(text.contains("https://"), text)
        XCTAssertTrue(text.contains("This is bold and code, see the docs."), text)
        XCTAssertTrue(text.contains("Code block skipped."), text)
        XCTAssertTrue(text.contains("one") && text.contains("two"), text)
    }

    // MARK: - Export

    func testAChatExportsAsMarkdownWithoutErrorsOrNotices() {
        let messages = chat + [ChatMessage(role: "error", content: "oops"), ChatMessage(role: "notice", content: "Usage")]
        let text = ChatExport.markdown(title: "My chat", messages: messages, date: isoDate("2026-10-13T12:00:00Z"))
        XCTAssertTrue(text.hasPrefix("# My chat\n"), text)
        XCTAssertTrue(text.contains("Exported from Gatita on 2026-10-13"), text)
        XCTAssertTrue(text.contains("## You\n\nfirst\n\n## Gatita\n\none"), text)
        XCTAssertFalse(text.contains("oops") || text.contains("Usage"), text)
    }

    func testExportFileNamesAreSafe() {
        XCTAssertEqual(ChatExport.fileName(for: "What is 2/3: a fraction?"), "What is 2-3- a fraction-.md")
        XCTAssertEqual(ChatExport.fileName(for: "   "), "Gatita chat.md")
    }

    // MARK: - Your own skills

    func testYourSkillsAreSavedAndLoaded() throws {
        let file = temporaryFolder(self).appendingPathComponent("my-skills.json")
        XCTAssertEqual(MySkills.load(from: file), [])
        let skills = [Skill(id: "my-tone", name: "Tone", instructions: "Be brief.")]
        MySkills.save(skills, to: file)
        XCTAssertEqual(MySkills.load(from: file), skills)
    }

    func testAYourSkillIdIsMadeFromItsNameAndNeverClashes() {
        XCTAssertEqual(MySkills.id(for: "Email Writer!", taken: []), "my-email-writer")
        XCTAssertEqual(MySkills.id(for: "Email Writer", taken: ["my-email-writer"]), "my-email-writer-2")
        XCTAssertEqual(MySkills.id(for: "!!!", taken: []), "my-skill")
        XCTAssertFalse(Skills.all.map(\.id).contains { $0.hasPrefix("my-") }, "built-in ids never start with my-")
    }
}

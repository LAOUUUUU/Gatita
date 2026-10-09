//
//  AgentLoopTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// The chat loop against the mock Gatita API: tool calls, streaming order, skills, and ask_user.
final class AgentLoopTests: XCTestCase {
    private static var mock: Process?
    private var root: URL!
    private var readOnly: ProjectTools!

    override class func setUp() {
        super.setUp()
        mock = try? MockGatita.start()
    }

    override class func tearDown() {
        mock?.terminate()
        mock = nil
        super.tearDown()
    }

    override func setUpWithError() throws {
        root = try makeProjectFixture(self)
        readOnly = ProjectTools(root: root, allowWrites: false)
    }

    func testToolLoopReturnsTheFinalText() async throws {
        let client = GatitaClient(apiKey: "test-key", baseURL: MockGatita.base, tools: readOnly)
        let reply = try await client.send(messages: [ChatMessage(role: "user", content: "what files are there?")])
        XCTAssertEqual(reply, "mock: found App/GatitaApp.swift")
    }

    func testChatWithoutAFolderSendsNoToolInstructions() async throws {
        let plain = GatitaClient(apiKey: "test-key", baseURL: MockGatita.base, tools: nil)
        let reply = try await plain.send(messages: [ChatMessage(role: "user", content: "hi")])
        XCTAssertEqual(reply, "mock: no tool instructions")
    }

    func testAWrongKeyThrows() async {
        let badKey = GatitaClient(apiKey: "wrong", baseURL: MockGatita.base, tools: readOnly)
        do {
            _ = try await badKey.send(messages: [ChatMessage(role: "user", content: "hi")])
            XCTFail("a wrong key returned a reply")
        } catch {
            // Expected: the error is surfaced, not a silent empty reply.
        }
    }

    func testStreamEmitsReasoningToolAndTextInOrder() async throws {
        let client = GatitaClient(apiKey: "test-key", baseURL: MockGatita.base, tools: readOnly)
        var events: [String] = []
        let final = try await client.stream(messages: [ChatMessage(role: "user", content: "what files are there?")]) { event in
            switch event {
            case .reasoning(let text):
                events.append("reasoning:\(text)")
            case .text(let text):
                events.append("text:\(text)")
            case .question(let text):
                events.append("question:\(text)")
            case .toolStarted(let id, let name, let arguments):
                events.append("start:\(id):\(name):\(arguments)")
            case .toolFinished(let id, _, let result):
                events.append("done:\(id):\(result.contains("App/GatitaApp.swift"))")
            }
        }
        XCTAssertEqual(final, "mock: found App/GatitaApp.swift")
        XCTAssertEqual(events, [
            "reasoning:Looking at ",
            "reasoning:the project.",
            "text:Let me look. ",
            "start:t1:list_files:{\"tool\": \"list_files\", \"path\": \".\"}",
            "done:t1:true",
            "text:mock: found ",
            "text:App/GatitaApp.swift",
        ])
    }

    func testNoSkillAddsNothingAndTheWebSkillHasItsInstructions() {
        XCTAssertNil(Skills.instructions(for: "none"))
        XCTAssertEqual(Skills.instructions(for: "web")?.contains("layout"), true)
    }

    func testSkillInstructionsReachTheModel() async throws {
        let skilled = GatitaClient(apiKey: "test-key", baseURL: MockGatita.base, extraInstructions: "SKILL-TEST")
        let reply = try await skilled.send(messages: [ChatMessage(role: "user", content: "hi")])
        XCTAssertEqual(reply, "mock: skill seen")
    }

    func testAskUserSendsTheQuestionAndNoToolRuns() async throws {
        let asker = GatitaClient(apiKey: "test-key", baseURL: MockGatita.base, tools: readOnly)
        var asked: [String] = []
        let answer = try await asker.stream(messages: [ChatMessage(role: "user", content: "ASK-ME which file")]) { event in
            switch event {
            case .question(let text):
                asked.append("question:\(text)")
            case .toolStarted(_, let name, _):
                asked.append("tool:\(name)")
            default:
                break
            }
        }
        XCTAssertEqual(asked, ["question:Which file should I read?"])
        XCTAssertTrue(answer.isEmpty)
    }
}

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
        mock?.waitUntilExit()
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
            case .usage:
                break
            case .toolFinished(let id, _, let result):
                events.append("done:\(id):\(result.contains("App/GatitaApp.swift"))")
            case .safetyStop:
                events.append("safety")
            case .fileChanged, .waiting:
                break
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

    func testASubagentAnswersItsTask() async throws {
        let registry = TaskRegistry()
        let client = GatitaClient(apiKey: "test-key", baseURL: MockGatita.base)
        let id = registry.spawnAgent(task: "hi", client: client)
        let answer = await registry.agentResult(id)
        XCTAssertEqual(answer, "mock: no tool instructions")
        XCTAssertEqual(registry.agents.first?.status, .done)
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

    // MARK: - Replies that used to just end

    private func runScenario(_ marker: String, tools: ProjectTools? = nil) async throws -> (text: String, events: [String]) {
        let client = GatitaClient(apiKey: "test-key", baseURL: MockGatita.base, tools: tools ?? readOnly)
        var events: [String] = []
        let text = try await client.stream(messages: [ChatMessage(role: "user", content: "\(marker) please")]) { event in
            switch event {
            case .text(let piece): events.append("text:\(piece)")
            case .toolStarted(_, let name, _): events.append("tool:\(name)")
            case .waiting(let seconds): events.append("waiting:\(seconds)")
            default: break
            }
        }
        return (text, events)
    }

    func testAnEmptyReplyAfterAToolResultIsAskedToAnswer() async throws {
        let result = try await runScenario("EMPTY-AFTER-TOOL")
        XCTAssertEqual(result.text, "mock: recovered after an empty reply")
        XCTAssertEqual(result.events.filter { $0.hasPrefix("tool:") }, ["tool:list_files"])
    }

    func testAReplyCutOffByTheLengthLimitIsContinued() async throws {
        let result = try await runScenario("CUT-OFF")
        XCTAssertEqual(result.text, "mock: first half, second half.")
    }

    func testAToolCallWithoutItsClosingTagStillRuns() async throws {
        let result = try await runScenario("NO-CLOSE-TAG")
        XCTAssertEqual(result.text, "mock: found App/GatitaApp.swift")
        XCTAssertEqual(result.events.filter { $0.hasPrefix("tool:") }, ["tool:list_files"])
    }

    func testAToolCallCutOffMidwayIsAskedForAgainAndNeverShown() async throws {
        let result = try await runScenario("BROKEN-BLOCK")
        XCTAssertEqual(result.text, "mock: found App/GatitaApp.swift")
        XCTAssertFalse(result.events.contains { $0.hasPrefix("text:") && $0.contains("list_fi") }, "the broken block was shown")
    }

    func testAReplyThatEndsInAColonIsAskedOnceToGoOn() async throws {
        let result = try await runScenario("COLON-END")
        XCTAssertEqual(result.text, "Checking the task:\n\nmock: done after the nudge.")
        XCTAssertEqual(result.events, ["text:Checking the task:", "text:\n\n", "text:mock: done after the nudge."])
    }

    func testAReplyThatKeepsComingBackEmptyEndsWithAnError() async {
        do {
            _ = try await runScenario("ALWAYS-EMPTY")
            XCTFail("an empty reply was accepted")
        } catch GatitaError.endedEarly(let ending) {
            XCTAssertEqual(ending, .empty)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testAConnectionThatClosesEarlyEndsWithAnError() async {
        do {
            _ = try await runScenario("DROPPED")
            XCTFail("a reply that was cut off was accepted")
        } catch GatitaError.endedEarly(let ending) {
            XCTAssertEqual(ending, .closedEarly)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testARateLimitIsWaitedOutAndTheRequestSentAgain() async throws {
        let result = try await runScenario("RATE-LIMIT-ONCE")
        XCTAssertEqual(result.text, "mock: answered after the rate limit")
        XCTAssertTrue(result.events.contains("waiting:1"), "\(result.events)")
    }

    func testARateLimitThatLastsEndsWithTheServersError() async {
        do {
            _ = try await runScenario("RATE-LIMIT-ALWAYS")
            XCTFail("a reply that was always rate limited was accepted")
        } catch GatitaError.http(let status, let body) {
            XCTAssertEqual(status, 429)
            XCTAssertTrue(body.contains("Rate limit"), body)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testABatchRunsEachCallAndSendsBackAllTheResultsInOneStep() async throws {
        let result = try await runScenario("BATCH-TEST")
        XCTAssertEqual(result.text, "mock: batch ok")
        XCTAssertEqual(result.events.filter { $0.hasPrefix("tool:") }, ["tool:list_files", "tool:read_file"])
    }
}

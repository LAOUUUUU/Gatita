//
//  PullRequestTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// Pull requests: git status parsing, branch checks, the planned git and gh steps, and AI-written text and tags.
final class PullRequestTests: XCTestCase {
    func testGitStatusIsParsed() {
        let changes = GitChanges.parse(" M App/GatitaApp.swift\nM  Shared/Models/Skills.swift\n?? Shared/Plugins/\nR  old.swift -> new.swift\n")
        XCTAssertTrue(changes.contains { $0.path == "App/GatitaApp.swift" && $0.kind == .modified && !$0.isStaged })
        XCTAssertTrue(changes.contains { $0.path == "Shared/Models/Skills.swift" && $0.kind == .modified && $0.isStaged })
        XCTAssertTrue(changes.contains { $0.path == "Shared/Plugins/" && $0.kind == .untracked })
        XCTAssertTrue(changes.contains { $0.path == "new.swift" && $0.kind == .renamed })
    }

    func testBranchNamesAreChecked() {
        XCTAssertTrue(PullRequestPlan.isValidBranch("gatita/fix-buttons"))
        XCTAssertFalse(PullRequestPlan.isValidBranch("bad name"))
        XCTAssertFalse(PullRequestPlan.isValidBranch("-x"))
        XCTAssertFalse(PullRequestPlan.isValidBranch("a..b"))
    }

    func testPlanCreatesTheBranchFirstAndCommitsOnlyTheChosenFiles() {
        let steps = PullRequestPlan.steps(branch: "gatita/fix", base: "main", files: ["App/GatitaApp.swift"],
                                          commitMessage: "Fix title", title: "Fix title", body: "Body")
        XCTAssertEqual(steps?.first, ["git", "checkout", "-b", "gatita/fix"])
        XCTAssertEqual(steps?.contains(["git", "add", "--", "App/GatitaApp.swift"]), true)
        XCTAssertEqual(steps?.contains(["git", "commit", "-m", "Fix title", "--", "App/GatitaApp.swift"]), true)
        XCTAssertEqual(steps?.contains(["git", "push", "-u", "origin", "gatita/fix"]), true)
        XCTAssertEqual(steps?.last, ["gh", "pr", "create", "--base", "main", "--head", "gatita/fix", "--title", "Fix title", "--body", "Body"])
    }

    func testPlanRefusesNoFilesOrABadBranch() {
        XCTAssertNil(PullRequestPlan.steps(branch: "gatita/fix", base: "main", files: [], commitMessage: "x", title: "x", body: ""))
        XCTAssertNil(PullRequestPlan.steps(branch: "bad name", base: "main", files: ["a"], commitMessage: "x", title: "x", body: ""))
    }

    func testDraftJSONIsFoundInsideTheReply() {
        let draft = PullRequestDraft.parse("Sure! {\"title\": \"Fix tool logs\", \"body\": \"Adds logs.\", \"labels\": [\"Bug Fix\", \"tests!\", \"\"]} Thanks")
        XCTAssertEqual(draft?.title, "Fix tool logs")
        XCTAssertEqual(draft?.body, "Adds logs.")
        XCTAssertEqual(draft?.labels, ["bug-fix", "tests"])
    }

    func testDraftWithoutATitleOrJSONIsRefused() {
        XCTAssertNil(PullRequestDraft.parse("{\"body\": \"x\"}"))
        XCTAssertNil(PullRequestDraft.parse("no braces here"))
    }

    func testTagCleaningDropsJunk() {
        XCTAssertEqual(PullRequestPlan.sanitizeLabel("  Feature / UI!! "), "feature-ui")
    }

    func testTagsAreCreatedAndAttachedAndTheRemoteCanBeRenamed() {
        let steps = PullRequestPlan.steps(remote: "main", branch: "gatita/fix", base: "main", files: ["a.swift"],
                                          commitMessage: "Fix", title: "Fix", body: "B", labels: ["bug-fix"])
        XCTAssertEqual(steps?.contains(["gh", "label", "create", "bug-fix", "--force"]), true)
        XCTAssertEqual(steps?.last, ["gh", "pr", "create", "--base", "main", "--head", "gatita/fix", "--title", "Fix", "--body", "B", "--label", "bug-fix"])
        XCTAssertEqual(steps?.contains(["git", "push", "-u", "main", "gatita/fix"]), true)
    }
}

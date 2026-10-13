//
//  GitWorktreesTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// Worktrees and branches from git, so the project bar can show the repo and pick the tree the folder is in.
final class GitWorktreesTests: XCTestCase {
    private let porcelain = """
    worktree /Users/you/Gatita
    HEAD 1111111111111111111111111111111111111111
    branch refs/heads/main

    worktree /Users/you/Gatita-feature
    HEAD 2222222222222222222222222222222222222222
    branch refs/heads/feature/bar

    worktree /Users/you/Gatita-detached
    HEAD 3333333333333333333333333333333333333333
    detached

    """

    func testEachWorktreeHasItsPathAndBranch() {
        let trees = GitWorktrees.parse(porcelain)
        XCTAssertEqual(trees.map(\.path), ["/Users/you/Gatita", "/Users/you/Gatita-feature", "/Users/you/Gatita-detached"])
        XCTAssertEqual(trees.map(\.branch), ["main", "feature/bar", nil])
    }

    func testTheNameIsTheLastPartOfThePath() {
        XCTAssertEqual(GitWorktrees.parse(porcelain).first?.name, "Gatita")
    }

    func testNoWorktreesMeansAnEmptyList() {
        XCTAssertEqual(GitWorktrees.parse(""), [])
    }

    func testTheWorktreeTheFolderIsInIsTheCurrentOne() {
        let trees = GitWorktrees.parse(porcelain)
        XCTAssertEqual(GitWorktrees.current(topLevel: "/Users/you/Gatita-feature", in: trees)?.branch, "feature/bar")
        XCTAssertNil(GitWorktrees.current(topLevel: "/Users/you/Other", in: trees))
    }

    func testATrailingSlashStillMatches() {
        let trees = GitWorktrees.parse(porcelain)
        XCTAssertEqual(GitWorktrees.current(topLevel: "/Users/you/Gatita/", in: trees)?.path, "/Users/you/Gatita")
    }
}

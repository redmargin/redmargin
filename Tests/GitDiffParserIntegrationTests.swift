import XCTest
@testable import RedmarginLib

/// Integration tests for GitDiffParser that require real git repos
final class GitDiffParserIntegrationTests: XCTestCase {
    private var helper: GitTestHelper!

    override func setUp() {
        super.setUp()
        helper = GitTestHelper()
        try? helper.setUp()
    }

    override func tearDown() {
        helper.tearDown()
        super.tearDown()
    }

    func testAddedLines() async throws {
        // Create repo with initial file
        let repoURL = try helper.createRepo(named: "test-repo")
        let fileURL = try helper.createFile(
            named: "test.md",
            content: "Line 1\nLine 2\nLine 3\n",
            in: repoURL
        )
        try helper.commit(message: "Initial commit", in: repoURL)

        // Add lines at end
        try "Line 1\nLine 2\nLine 3\nLine 4\nLine 5\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let result = try await GitDiffParser.parseChanges(forFile: fileURL, repoRoot: repoURL)

        XCTAssertFalse(result.isUntracked)
        XCTAssertTrue(result.changedRanges.contains(4...5))
        XCTAssertTrue(result.deletedAnchors.isEmpty)
    }

    func testModifiedLines() async throws {
        let repoURL = try helper.createRepo(named: "test-repo")
        let fileURL = try helper.createFile(
            named: "test.md",
            content: "Line 1\nOriginal Line 2\nLine 3\n",
            in: repoURL
        )
        try helper.commit(message: "Initial commit", in: repoURL)

        // Modify line 2
        try "Line 1\nModified Line 2\nLine 3\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let result = try await GitDiffParser.parseChanges(forFile: fileURL, repoRoot: repoURL)

        XCTAssertFalse(result.isUntracked)
        XCTAssertTrue(result.changedRanges.contains(2...2))
    }

    func testDeletedLines() async throws {
        let repoURL = try helper.createRepo(named: "test-repo")
        let fileURL = try helper.createFile(
            named: "test.md",
            content: "Line 1\nLine 2\nLine 3\nLine 4\nLine 5\n",
            in: repoURL
        )
        try helper.commit(message: "Initial commit", in: repoURL)

        // Delete lines 2-3
        try "Line 1\nLine 4\nLine 5\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let result = try await GitDiffParser.parseChanges(forFile: fileURL, repoRoot: repoURL)

        XCTAssertFalse(result.isUntracked)
        XCTAssertTrue(result.changedRanges.isEmpty)
        XCTAssertFalse(result.deletedAnchors.isEmpty)
    }

    func testMultipleHunks() async throws {
        let repoURL = try helper.createRepo(named: "test-repo")
        let fileURL = try helper.createFile(
            named: "test.md",
            content: "Line 1\nLine 2\nLine 3\nLine 4\nLine 5\nLine 6\nLine 7\nLine 8\nLine 9\nLine 10\n",
            in: repoURL
        )
        try helper.commit(message: "Initial commit", in: repoURL)

        // Modify line 2 and line 8
        try "Line 1\nChanged 2\nLine 3\nLine 4\nLine 5\nLine 6\nLine 7\nChanged 8\nLine 9\nLine 10\n"
            .write(to: fileURL, atomically: true, encoding: .utf8)

        let result = try await GitDiffParser.parseChanges(forFile: fileURL, repoRoot: repoURL)

        XCTAssertEqual(result.changedRanges.count, 2)
        XCTAssertTrue(result.changedRanges.contains(2...2))
        XCTAssertTrue(result.changedRanges.contains(8...8))
    }

    func testCleanFile() async throws {
        let repoURL = try helper.createRepo(named: "test-repo")
        let fileURL = try helper.createFile(
            named: "test.md",
            content: "No changes here\n",
            in: repoURL
        )
        try helper.commit(message: "Initial commit", in: repoURL)

        // No changes made
        let result = try await GitDiffParser.parseChanges(forFile: fileURL, repoRoot: repoURL)

        XCTAssertEqual(result, GitChangeResult.empty)
    }

    func testUntrackedFile() async throws {
        let repoURL = try helper.createRepo(named: "test-repo")

        // Create initial commit so HEAD exists
        try helper.createFile(named: "initial.md", content: "Initial\n", in: repoURL)
        try helper.commit(message: "Initial commit", in: repoURL)

        // Create untracked file (not added to git)
        let fileURL = try helper.createFile(
            named: "untracked.md",
            content: "Line 1\nLine 2\nLine 3\n",
            in: repoURL
        )

        let result = try await GitDiffParser.parseChanges(forFile: fileURL, repoRoot: repoURL)

        XCTAssertTrue(result.isUntracked)
        XCTAssertEqual(result.changedRanges.count, 1)
        XCTAssertEqual(result.changedRanges.first, 1...3)
    }

    func testMixedAddAndDelete() async throws {
        let repoURL = try helper.createRepo(named: "test-repo")
        let fileURL = try helper.createFile(
            named: "test.md",
            content: "Line 1\nLine 2\nLine 3\nLine 4\n",
            in: repoURL
        )
        try helper.commit(message: "Initial commit", in: repoURL)

        // Delete line 2, add new lines at end
        try "Line 1\nLine 3\nLine 4\nNew Line 5\nNew Line 6\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let result = try await GitDiffParser.parseChanges(forFile: fileURL, repoRoot: repoURL)

        XCTAssertFalse(result.isUntracked)
        // Should have added lines and deleted anchors
        XCTAssertFalse(result.changedRanges.isEmpty)
        XCTAssertFalse(result.deletedAnchors.isEmpty)
    }

    func testFileInSubdirectory() async throws {
        let repoURL = try helper.createRepo(named: "test-repo")
        let docsDir = try helper.createDirectory(named: "docs/api", in: repoURL)
        let fileURL = try helper.createFile(
            named: "guide.md",
            content: "Original content\n",
            in: docsDir
        )
        try helper.commit(message: "Initial commit", in: repoURL)

        // Modify the file
        try "Modified content\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let result = try await GitDiffParser.parseChanges(forFile: fileURL, repoRoot: repoURL)

        XCTAssertFalse(result.isUntracked)
        XCTAssertTrue(result.changedRanges.contains(1...1))
    }

    func testNewRepoNoCommits() async throws {
        // Create repo but don't make any commits
        let repoURL = try helper.createRepo(named: "new-repo")
        let fileURL = try helper.createFile(
            named: "test.md",
            content: "Line 1\nLine 2\n",
            in: repoURL
        )
        // Don't commit - HEAD doesn't exist

        let result = try await GitDiffParser.parseChanges(forFile: fileURL, repoRoot: repoURL)

        // Should treat as untracked since there's no HEAD
        XCTAssertTrue(result.isUntracked)
        XCTAssertEqual(result.changedRanges.first, 1...2)
    }

    func testStagedButNotCommitted() async throws {
        let repoURL = try helper.createRepo(named: "test-repo")

        // Create initial commit
        try helper.createFile(named: "initial.md", content: "Initial\n", in: repoURL)
        try helper.commit(message: "Initial commit", in: repoURL)

        // Create and stage a new file, but don't commit
        let fileURL = try helper.createFile(
            named: "staged.md",
            content: "Staged content\nLine 2\n",
            in: repoURL
        )

        // Stage the file
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["add", "staged.md"]
        process.currentDirectoryURL = repoURL
        try process.run()
        process.waitUntilExit()

        // File is staged but not committed - should be considered untracked vs HEAD
        let result = try await GitDiffParser.parseChanges(forFile: fileURL, repoRoot: repoURL)

        // git diff HEAD shows the file as added
        XCTAssertEqual(result.changedRanges.first, 1...2)
    }
}

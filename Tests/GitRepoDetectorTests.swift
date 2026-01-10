import XCTest
@testable import RedmarginLib

final class GitRepoDetectorTests: XCTestCase {
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

    func testDetectsRepoRoot() async throws {
        // Create a git repo with a file
        let repoURL = try helper.createRepo(named: "test-repo")
        let fileURL = try helper.createFile(named: "README.md", content: "# Test", in: repoURL)
        try helper.commit(message: "Initial commit", in: repoURL)

        // Detect repo root
        let detectedRoot = try await GitRepoDetector.detectRepoRoot(forFile: fileURL)

        // Resolve symlinks for comparison (macOS /var -> /private/var)
        let expectedPath = repoURL.resolvingSymlinksInPath().path
        let actualPath = detectedRoot?.resolvingSymlinksInPath().path

        XCTAssertEqual(actualPath, expectedPath)
    }

    func testDetectsRepoRootFromSubdirectory() async throws {
        // Create repo with nested directory structure
        let repoURL = try helper.createRepo(named: "nested-repo")
        let docsDir = try helper.createDirectory(named: "docs/api", in: repoURL)
        let fileURL = try helper.createFile(named: "guide.md", content: "# Guide", in: docsDir)
        try helper.commit(message: "Add docs", in: repoURL)

        // Detect from nested file
        let detectedRoot = try await GitRepoDetector.detectRepoRoot(forFile: fileURL)

        // Should return repo root, not docs/api
        let expectedPath = repoURL.resolvingSymlinksInPath().path
        let actualPath = detectedRoot?.resolvingSymlinksInPath().path

        XCTAssertEqual(actualPath, expectedPath)
    }

    func testReturnsNilForNonRepoFile() async throws {
        // Create a file NOT in a git repo
        let dirURL = try helper.createDirectory(named: "not-a-repo", in: helper.rootDirectory)
        let fileURL = try helper.createFile(named: "orphan.md", content: "# Orphan", in: dirURL)

        // Should return nil, not throw
        let detectedRoot = try await GitRepoDetector.detectRepoRoot(forFile: fileURL)

        XCTAssertNil(detectedRoot)
    }

    func testHandlesSubmodule() async throws {
        // Create main repo and submodule repo
        let mainRepoURL = try helper.createRepo(named: "main-repo")
        let subRepoURL = try helper.createRepo(named: "sub-repo")

        // Add a file to submodule and commit
        try helper.createFile(named: "sub.md", content: "# Sub", in: subRepoURL)
        try helper.commit(message: "Initial sub commit", in: subRepoURL)

        // Add submodule to main repo
        try helper.addSubmodule(subRepoURL, at: "libs/sub", in: mainRepoURL)
        try helper.commit(message: "Add submodule", in: mainRepoURL)

        // Create a file in the submodule within main repo
        let submodulePath = mainRepoURL.appendingPathComponent("libs/sub")
        let fileInSub = try helper.createFile(named: "new.md", content: "# New", in: submodulePath)

        // Detect should return submodule root, not main repo root
        let detectedRoot = try await GitRepoDetector.detectRepoRoot(forFile: fileInSub)

        let expectedPath = submodulePath.resolvingSymlinksInPath().path
        let actualPath = detectedRoot?.resolvingSymlinksInPath().path

        XCTAssertEqual(actualPath, expectedPath)
    }

    func testHandlesMissingFile() async throws {
        // Path to a file that doesn't exist, in a directory that doesn't exist either
        let missingFile = helper.rootDirectory
            .appendingPathComponent("nonexistent")
            .appendingPathComponent("missing.md")

        // Should return nil (not in a repo), not throw
        let detectedRoot = try await GitRepoDetector.detectRepoRoot(forFile: missingFile)

        XCTAssertNil(detectedRoot)
    }

    func testPathContainsSpaces() async throws {
        // Create repo at path with spaces
        let repoURL = try helper.createRepo(named: "repo with spaces")
        let fileURL = try helper.createFile(named: "file with spaces.md", content: "# Test", in: repoURL)
        try helper.commit(message: "Initial commit", in: repoURL)

        let detectedRoot = try await GitRepoDetector.detectRepoRoot(forFile: fileURL)

        let expectedPath = repoURL.resolvingSymlinksInPath().path
        let actualPath = detectedRoot?.resolvingSymlinksInPath().path

        XCTAssertEqual(actualPath, expectedPath)
    }

    func testPathContainsUnicode() async throws {
        // Create repo at path with Unicode characters
        let repoURL = try helper.createRepo(named: "repo-日本語-émoji-🚀")
        let fileURL = try helper.createFile(named: "文档.md", content: "# 测试", in: repoURL)
        try helper.commit(message: "Initial commit", in: repoURL)

        let detectedRoot = try await GitRepoDetector.detectRepoRoot(forFile: fileURL)

        let expectedPath = repoURL.resolvingSymlinksInPath().path
        let actualPath = detectedRoot?.resolvingSymlinksInPath().path

        XCTAssertEqual(actualPath, expectedPath)
    }

    func testHandlesWorktree() async throws {
        // Create main repo with initial commit
        let mainRepoURL = try helper.createRepo(named: "main-repo")
        try helper.createFile(named: "main.md", content: "# Main", in: mainRepoURL)
        try helper.commit(message: "Initial commit", in: mainRepoURL)

        // Create a worktree
        let worktreeURL = try helper.createWorktree(named: "worktree", branch: "feature", in: mainRepoURL)

        // Create a file in the worktree
        let fileInWorktree = try helper.createFile(named: "feature.md", content: "# Feature", in: worktreeURL)

        // Detect should return worktree root, not main repo root
        let detectedRoot = try await GitRepoDetector.detectRepoRoot(forFile: fileInWorktree)

        let expectedPath = worktreeURL.resolvingSymlinksInPath().path
        let actualPath = detectedRoot?.resolvingSymlinksInPath().path

        XCTAssertEqual(actualPath, expectedPath)
    }
}

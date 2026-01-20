import XCTest
@testable import RedmarginCore

final class LocalFileProviderTests: XCTestCase {
    var tempDir: URL!
    var provider: LocalFileProvider!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        provider = LocalFileProvider()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Read Tests

    func testReadFile() async throws {
        let testFile = tempDir.appendingPathComponent("test.md")
        let content = "# Hello World\n\nThis is a test."
        try content.write(to: testFile, atomically: true, encoding: .utf8)

        let readContent = try await provider.readFile(at: testFile.path)
        XCTAssertEqual(readContent, content)
    }

    func testReadFileMissing() async throws {
        let missingFile = tempDir.appendingPathComponent("missing.md")

        do {
            _ = try await provider.readFile(at: missingFile.path)
            XCTFail("Expected error for missing file")
        } catch {
            // Expected - file doesn't exist
            XCTAssertTrue(error is CocoaError)
        }
    }

    func testReadFileEmptyFile() async throws {
        let emptyFile = tempDir.appendingPathComponent("empty.md")
        try "".write(to: emptyFile, atomically: true, encoding: .utf8)

        let readContent = try await provider.readFile(at: emptyFile.path)
        XCTAssertEqual(readContent, "")
    }

    // MARK: - Write Tests

    func testWriteFile() async throws {
        let testFile = tempDir.appendingPathComponent("write-test.md")
        let content = "# Test Content"

        try await provider.writeFile(at: testFile.path, content: content)

        let readContent = try String(contentsOf: testFile, encoding: .utf8)
        XCTAssertEqual(readContent, content)
    }

    func testWriteFileAtomic() async throws {
        // Test that write is atomic by checking the file exists with full content
        let testFile = tempDir.appendingPathComponent("atomic-test.md")
        let content = String(repeating: "Test line\n", count: 1000)

        try await provider.writeFile(at: testFile.path, content: content)

        let readContent = try String(contentsOf: testFile, encoding: .utf8)
        XCTAssertEqual(readContent, content)
    }

    func testWriteFileOverwrite() async throws {
        let testFile = tempDir.appendingPathComponent("overwrite-test.md")

        try await provider.writeFile(at: testFile.path, content: "Original")
        try await provider.writeFile(at: testFile.path, content: "Updated")

        let readContent = try String(contentsOf: testFile, encoding: .utf8)
        XCTAssertEqual(readContent, "Updated")
    }

    // MARK: - Watch Tests

    func testWatchFile() async throws {
        let testFile = tempDir.appendingPathComponent("watch-test.md")
        try "Initial".write(to: testFile, atomically: true, encoding: .utf8)

        let expectation = XCTestExpectation(description: "Watch callback")
        let token = await provider.watchFile(at: testFile.path) {
            expectation.fulfill()
        }

        // Give watcher time to set up
        try await Task.sleep(nanoseconds: 100_000_000)

        // Modify file
        try "Modified".write(to: testFile, atomically: true, encoding: .utf8)

        await fulfillment(of: [expectation], timeout: 2.0)
        await provider.unwatch(token)
    }

    func testUnwatchStopsNotifications() async throws {
        let testFile = tempDir.appendingPathComponent("unwatch-test.md")
        try "Initial".write(to: testFile, atomically: true, encoding: .utf8)

        var callCount = 0
        let token = await provider.watchFile(at: testFile.path) {
            callCount += 1
        }

        try await Task.sleep(nanoseconds: 100_000_000)

        // Unwatch
        await provider.unwatch(token)

        // Modify file
        try "Modified".write(to: testFile, atomically: true, encoding: .utf8)

        try await Task.sleep(nanoseconds: 200_000_000)

        // Should not have been called after unwatch
        XCTAssertEqual(callCount, 0)
    }

    // MARK: - Git Tests

    func testDetectGitRepoNoRepo() async throws {
        let testFile = tempDir.appendingPathComponent("no-repo.md")
        try "Test".write(to: testFile, atomically: true, encoding: .utf8)

        let repoRoot = try await provider.detectGitRepo(for: testFile.path)
        XCTAssertNil(repoRoot)
    }

    func testGitOperationsInRepo() async throws {
        // Create a git repo in temp dir
        let repoDir = tempDir.appendingPathComponent("test-repo")
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)

        // Initialize git repo
        _ = try await ProcessRunner.run(executable: "git", arguments: ["-C", repoDir.path, "init"])
        _ = try await ProcessRunner.run(
            executable: "git",
            arguments: ["-C", repoDir.path, "config", "user.email", "test@test.com"]
        )
        _ = try await ProcessRunner.run(
            executable: "git",
            arguments: ["-C", repoDir.path, "config", "user.name", "Test"]
        )

        // Create and commit a file
        let testFile = repoDir.appendingPathComponent("test.md")
        try "# Original".write(to: testFile, atomically: true, encoding: .utf8)
        _ = try await ProcessRunner.run(executable: "git", arguments: ["-C", repoDir.path, "add", "test.md"])
        _ = try await ProcessRunner.run(executable: "git", arguments: ["-C", repoDir.path, "commit", "-m", "Initial"])

        // Detect repo
        let detectedRoot = try await provider.detectGitRepo(for: testFile.path)
        XCTAssertNotNil(detectedRoot)
        XCTAssertTrue(detectedRoot?.hasSuffix("test-repo") ?? false)

        // Modify file
        try "# Modified".write(to: testFile, atomically: true, encoding: .utf8)

        // Get diff
        let diff = try await provider.gitDiff(for: testFile.path, repoRoot: detectedRoot!)
        XCTAssertNotEqual(diff, .empty, "Expected changes in diff")
    }
}

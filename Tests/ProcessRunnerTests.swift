import XCTest
import Foundation
@testable import RedmarginLib
@testable import RedmarginCore

class ProcessRunnerTests: XCTestCase {

    func testRunsSimpleCommand() async throws {
        let result = try await ProcessRunner.run(
            executable: "echo",
            arguments: ["hello"]
        )

        XCTAssertEqual(result.stdout, "hello\n")
        XCTAssertEqual(result.stderr, "")
        XCTAssertEqual(result.exitCode, 0)
    }

    func testCapturesStderr() async throws {
        // Use bash to write to stderr
        let result = try await ProcessRunner.run(
            executable: "bash",
            arguments: ["-c", "echo error >&2"]
        )

        XCTAssertEqual(result.stdout, "")
        XCTAssertEqual(result.stderr, "error\n")
        XCTAssertEqual(result.exitCode, 0)
    }

    func testReturnsExitCode() async throws {
        let result = try await ProcessRunner.run(
            executable: "bash",
            arguments: ["-c", "exit 42"]
        )

        XCTAssertEqual(result.exitCode, 42)
    }

    func testHandlesWorkingDirectory() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let result = try await ProcessRunner.run(
            executable: "pwd",
            workingDirectory: tempDir
        )

        // pwd output should match the temp directory (resolve symlinks for /var -> /private/var)
        let expectedPath = tempDir.path.replacingOccurrences(of: "/var/", with: "/private/var/")
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), expectedPath)
        XCTAssertEqual(result.exitCode, 0)
    }

    func testHandlesMultipleArguments() async throws {
        let result = try await ProcessRunner.run(
            executable: "echo",
            arguments: ["one", "two", "three"]
        )

        XCTAssertEqual(result.stdout, "one two three\n")
    }

    func testHandlesArgumentsWithSpaces() async throws {
        let result = try await ProcessRunner.run(
            executable: "echo",
            arguments: ["hello world", "foo bar"]
        )

        XCTAssertEqual(result.stdout, "hello world foo bar\n")
    }

    func testTerminateIfRunningIsNoOpBeforeLaunch() {
        let process = Process()

        process.terminateIfRunning()

        XCTAssertFalse(process.isRunning)
    }

    /// Regression: every spawned command must carry GIT_OPTIONAL_LOCKS=0 so a
    /// watch-driven `git status`/`git diff` cannot refresh and rewrite `.git/index`,
    /// which would re-fire the remote helper's git watcher and spawn git in a loop
    /// until the daemon ran out of file descriptors.
    func testInjectsGitOptionalLocksDisabled() async throws {
        let result = try await ProcessRunner.run(
            executable: "bash",
            arguments: ["-c", "printf %s \"$GIT_OPTIONAL_LOCKS\""]
        )

        XCTAssertEqual(result.stdout, "0")
        XCTAssertEqual(result.exitCode, 0)
    }

    func testPreservesInheritedEnvironment() async throws {
        // Injecting GIT_OPTIONAL_LOCKS must not wipe the rest of the environment
        // (PATH etc. are needed for the /usr/bin/env executable-resolution path).
        let result = try await ProcessRunner.run(
            executable: "bash",
            arguments: ["-c", "printf %s \"$PATH\""]
        )

        XCTAssertFalse(result.stdout.isEmpty, "PATH should be inherited")
        XCTAssertEqual(result.exitCode, 0)
    }
}

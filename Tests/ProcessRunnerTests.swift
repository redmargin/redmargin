import XCTest
@testable import RedmarginLib

final class ProcessRunnerTests: XCTestCase {

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
}

import Foundation

/// Result of running a process
public struct ProcessResult {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
}

/// Async wrapper around Process for running shell commands
public enum ProcessRunner {

    /// Known executable paths for security hardening
    /// Prefer absolute paths to prevent PATH manipulation attacks
    private static let knownPaths: [String: String] = [
        "git": "/usr/bin/git"
    ]

    /// Runs an executable with arguments and returns the result
    /// - Parameters:
    ///   - executable: Path to the executable (e.g., "/usr/bin/git" or just "git")
    ///   - arguments: Command-line arguments
    ///   - workingDirectory: Optional working directory for the process
    ///   - timeout: Optional timeout in seconds (default: no timeout)
    /// - Returns: ProcessResult with stdout, stderr, and exit code
    /// - Throws: ProcessRunnerError if the process cannot be started or times out
    public static func run(
        executable: String,
        arguments: [String] = [],
        workingDirectory: URL? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> ProcessResult {
        let process = Process()

        // Resolve executable path
        if executable.hasPrefix("/") {
            // Already absolute
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
        } else if let knownPath = knownPaths[executable],
                  FileManager.default.fileExists(atPath: knownPath) {
            // Use known absolute path for security
            process.executableURL = URL(fileURLWithPath: knownPath)
            process.arguments = arguments
        } else {
            // Fall back to PATH resolution via env
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executable] + arguments
        }

        if let workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }

        // Run git in read-only mode for status/diff: GIT_OPTIONAL_LOCKS=0 stops git
        // from refreshing and rewriting `.git/index` during `status`/`diff`. Without
        // it, a watch-triggered `git status` writes the index, which re-fires the
        // remote helper's `.git/index` watcher, which triggers another status — a
        // runaway feedback loop that spawns git until the daemon exhausts its file
        // descriptors and every directory read fails. Harmless for non-git commands.
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Guarantee the pipe write ends are closed on EVERY exit path (success,
        // throw, timeout, cancellation, launch failure). The read ends are closed
        // by their own reader threads after EOF (below) so we never yank an FD out
        // from under a blocked read. Relying on ARC dealloc leaked descriptors: an
        // abandoned continuation or retained closure kept the Pipe alive, and over
        // hours of git polling the daemon hit its FD limit (EMFILE) and every
        // directory read began failing. Closing the write ends here also unblocks
        // any reader still waiting for EOF on the launch-failure path.
        defer {
            try? stdoutPipe.fileHandleForWriting.close()
            try? stderrPipe.fileHandleForWriting.close()
        }

        return try await withThrowingTaskGroup(of: ProcessResult.self) { group in
            group.addTask {
                return try await withCheckedThrowingContinuation { continuation in
                    // Drain both pipes concurrently on background threads, started
                    // BEFORE the child can fill them. The previous code read the
                    // pipes synchronously inside terminationHandler, which only runs
                    // AFTER the child exits — so a child whose output exceeded the
                    // 64KB pipe buffer (e.g. a large `git status`) blocked forever
                    // writing, never terminated, never got drained, and leaked its
                    // pipe FDs when the timeout killed it. Draining concurrently
                    // removes the deadlock entirely.
                    let readGroup = DispatchGroup()
                    let outBox = DataBox()
                    let errBox = DataBox()

                    readGroup.enter()
                    DispatchQueue.global().async {
                        let handle = stdoutPipe.fileHandleForReading
                        outBox.data = handle.readDataToEndOfFile()
                        try? handle.close()   // release the read FD on the thread that owns it
                        readGroup.leave()
                    }
                    readGroup.enter()
                    DispatchQueue.global().async {
                        let handle = stderrPipe.fileHandleForReading
                        errBox.data = handle.readDataToEndOfFile()
                        try? handle.close()
                        readGroup.leave()
                    }

                    process.terminationHandler = { terminatedProcess in
                        // Reads finish once the child exits and its write ends close
                        // (EOF). Wait for both before resuming so output isn't lost.
                        readGroup.notify(queue: DispatchQueue.global()) {
                            let result = ProcessResult(
                                stdout: String(data: outBox.data, encoding: .utf8) ?? "",
                                stderr: String(data: errBox.data, encoding: .utf8) ?? "",
                                exitCode: terminatedProcess.terminationStatus
                            )
                            continuation.resume(returning: result)
                        }
                    }

                    do {
                        try process.run()
                    } catch {
                        continuation.resume(throwing: ProcessRunnerError.launchFailed(error))
                    }
                }
            }

            if let timeout {
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    process.terminateIfRunning()
                    throw ProcessRunnerError.timeout(timeout)
                }
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

/// Mutable box so the background reader tasks can hand their data back to the
/// termination handler without capturing an `inout`.
private final class DataBox: @unchecked Sendable {
    var data = Data()
}

/// Errors that can occur when running a process
enum ProcessRunnerError: Error, LocalizedError {
    case launchFailed(Error)
    case timeout(TimeInterval)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let error):
            return "Failed to launch process: \(error.localizedDescription)"
        case .timeout(let seconds):
            return "Process timed out after \(Int(seconds)) seconds"
        }
    }
}

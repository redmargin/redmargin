import Foundation

/// Result of running a process
struct ProcessResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

/// Async wrapper around Process for running shell commands
enum ProcessRunner {

    /// Runs an executable with arguments and returns the result
    /// - Parameters:
    ///   - executable: Path to the executable (e.g., "/usr/bin/git" or just "git")
    ///   - arguments: Command-line arguments
    ///   - workingDirectory: Optional working directory for the process
    /// - Returns: ProcessResult with stdout, stderr, and exit code
    /// - Throws: ProcessRunnerError if the process cannot be started
    static func run(
        executable: String,
        arguments: [String] = [],
        workingDirectory: URL? = nil
    ) async throws -> ProcessResult {
        let process = Process()

        // Find executable in PATH if not an absolute path
        if executable.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: executable)
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executable] + arguments
        }

        if !executable.hasPrefix("/") {
            // Arguments already set above with env
        } else {
            process.arguments = arguments
        }

        if let workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return try await withCheckedThrowingContinuation { continuation in
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: ProcessRunnerError.launchFailed(error))
                return
            }

            process.waitUntilExit()

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""

            let result = ProcessResult(
                stdout: stdout,
                stderr: stderr,
                exitCode: process.terminationStatus
            )

            continuation.resume(returning: result)
        }
    }
}

/// Errors that can occur when running a process
enum ProcessRunnerError: Error, LocalizedError {
    case launchFailed(Error)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let error):
            return "Failed to launch process: \(error.localizedDescription)"
        }
    }
}

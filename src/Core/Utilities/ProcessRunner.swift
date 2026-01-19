import Foundation

/// Result of running a process
struct ProcessResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

/// Async wrapper around Process for running shell commands
enum ProcessRunner {

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
    /// - Returns: ProcessResult with stdout, stderr, and exit code
    /// - Throws: ProcessRunnerError if the process cannot be started
    static func run(
        executable: String,
        arguments: [String] = [],
        workingDirectory: URL? = nil
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

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { terminatedProcess in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                let result = ProcessResult(
                    stdout: stdout,
                    stderr: stderr,
                    exitCode: terminatedProcess.terminationStatus
                )

                continuation.resume(returning: result)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: ProcessRunnerError.launchFailed(error))
            }
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

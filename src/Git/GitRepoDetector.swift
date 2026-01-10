import Foundation

/// Detects whether a file is inside a Git repository and finds the repo root
enum GitRepoDetector {

    /// Detects the Git repository root for a given file
    /// - Parameter fileURL: URL of the file to check
    /// - Returns: URL of the repository root, or nil if the file is not in a Git repository
    /// - Throws: GitError for unexpected errors (git not found, permission denied, etc.)
    static func detectRepoRoot(forFile fileURL: URL) async throws -> URL? {
        // Get the directory containing the file
        let directory = fileURL.deletingLastPathComponent()

        // Run git rev-parse --show-toplevel from the file's directory
        let result: ProcessResult
        do {
            result = try await ProcessRunner.run(
                executable: "git",
                arguments: ["-C", directory.path, "rev-parse", "--show-toplevel"]
            )
        } catch let error as ProcessRunnerError {
            // Check if git is not found
            let errorMessage = error.localizedDescription.lowercased()
            if errorMessage.contains("no such file") || errorMessage.contains("not found") {
                throw GitError.gitNotFound
            }
            throw GitError.unexpectedError(error.localizedDescription)
        }

        // Exit code != 0 means not in a git repo (normal case, not an error)
        if result.exitCode != 0 {
            // Check for specific error conditions
            let stderr = result.stderr.lowercased()
            if stderr.contains("permission denied") {
                throw GitError.permissionDenied(directory.path)
            }
            // "fatal: not a git repository" is expected for non-repo files
            return nil
        }

        // Parse the repo root path from stdout
        let repoPath = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repoPath.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: repoPath)
    }
}

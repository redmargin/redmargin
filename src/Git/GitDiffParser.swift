import Foundation

/// Parses git diff output to extract changed line ranges
enum GitDiffParser {

    /// Parses changes for a file compared to HEAD
    /// - Parameters:
    ///   - fileURL: URL of the file to check
    ///   - repoRoot: URL of the git repository root
    /// - Returns: GitChangeResult with changed ranges and deleted anchors
    /// - Throws: GitError for git-related errors
    static func parseChanges(forFile fileURL: URL, repoRoot: URL) async throws -> GitChangeResult {
        // Compute relative path from repo root
        let relativePath = computeRelativePath(from: repoRoot, to: fileURL)

        // First check if file is tracked
        let isTracked = try await isFileTracked(relativePath: relativePath, repoRoot: repoRoot)

        if !isTracked {
            // Untracked file: all lines are "added"
            let lineCount = countLines(in: fileURL)
            return .untracked(lineCount: lineCount)
        }

        // Run git diff
        let diffOutput = try await runGitDiff(relativePath: relativePath, repoRoot: repoRoot)

        // Empty diff means clean file
        if diffOutput.isEmpty {
            return .empty
        }

        // Check for binary file
        if diffOutput.contains("Binary files") {
            return .empty
        }

        // Parse the diff output
        return parseDiffOutput(diffOutput)
    }

    /// Checks if a file is tracked by git
    private static func isFileTracked(relativePath: String, repoRoot: URL) async throws -> Bool {
        let result = try await ProcessRunner.run(
            executable: "git",
            arguments: ["ls-files", "--error-unmatch", "--", relativePath],
            workingDirectory: repoRoot
        )

        // Exit code 0 = tracked, non-zero = untracked
        return result.exitCode == 0
    }

    /// Runs git diff and returns the output
    private static func runGitDiff(relativePath: String, repoRoot: URL) async throws -> String {
        let result = try await ProcessRunner.run(
            executable: "git",
            arguments: ["diff", "--unified=0", "HEAD", "--", relativePath],
            workingDirectory: repoRoot
        )

        // Check for errors
        if result.exitCode != 0 {
            let stderr = result.stderr.lowercased()

            // "unknown revision HEAD" means no commits yet - treat as untracked
            if stderr.contains("unknown revision") {
                return ""
            }

            if stderr.contains("permission denied") {
                throw GitError.permissionDenied(relativePath)
            }

            // Other errors: log but don't crash, return empty
            return ""
        }

        return result.stdout
    }

    /// Parses diff output into GitChangeResult
    static func parseDiffOutput(_ output: String) -> GitChangeResult {
        var changedRanges: [ClosedRange<Int>] = []
        var deletedAnchors: [Int] = []

        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            guard line.hasPrefix("@@") else { continue }

            guard let hunk = DiffHunk.parse(hunkHeader: line) else { continue }

            if hunk.newCount > 0 {
                // Lines were added or modified
                let start = hunk.newStart
                let end = hunk.newStart + hunk.newCount - 1
                changedRanges.append(start...end)
            } else if hunk.oldCount > 0 {
                // Pure deletion: anchor at the line after deletion
                // newStart points to the line after where content was deleted
                deletedAnchors.append(hunk.newStart)
            }
        }

        return GitChangeResult(
            changedRanges: changedRanges,
            deletedAnchors: deletedAnchors,
            isUntracked: false
        )
    }

    /// Computes relative path from repo root to file
    private static func computeRelativePath(from repoRoot: URL, to fileURL: URL) -> String {
        let repoPath = repoRoot.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path

        if filePath.hasPrefix(repoPath) {
            var relative = String(filePath.dropFirst(repoPath.count))
            if relative.hasPrefix("/") {
                relative = String(relative.dropFirst())
            }
            return relative
        }

        // Fallback: just use the file name
        return fileURL.lastPathComponent
    }

    /// Counts lines in a file
    private static func countLines(in fileURL: URL) -> Int {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return 0
        }

        if content.isEmpty {
            return 0
        }

        // Count newlines, add 1 if file doesn't end with newline
        let newlineCount = content.filter { $0 == "\n" }.count
        return content.hasSuffix("\n") ? newlineCount : newlineCount + 1
    }
}

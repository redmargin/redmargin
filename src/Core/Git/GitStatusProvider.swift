import Foundation

public enum GitFileStatus: String, Codable, Equatable {
    case clean
    case modified
    case staged
    case untracked
    case conflict
}

public struct GitStatusSnapshot: Codable, Equatable {
    public let repoRoot: String?
    public let statuses: [String: GitFileStatus]

    public init(repoRoot: String?, statuses: [String: GitFileStatus]) {
        self.repoRoot = repoRoot
        self.statuses = statuses
    }

    public static let empty = GitStatusSnapshot(repoRoot: nil, statuses: [:])
}

/// Branch plus changed-file count for a workspace folder's repository.
public struct GitWorkspaceSummary: Equatable {
    public let branch: String
    public let changedCount: Int

    public init(branch: String, changedCount: Int) {
        self.branch = branch
        self.changedCount = changedCount
    }
}

public actor GitStatusProvider {
    public static let shared = GitStatusProvider()

    public init() {}

    /// Summary for a workspace folder, or nil when it is not inside a repo.
    public func summary(for directory: URL) async -> GitWorkspaceSummary? {
        let workingDirectory = resolvedDirectory(for: directory)

        guard let repoRoot = await repoRoot(for: workingDirectory) else {
            return nil
        }

        let branch = await currentBranch(in: repoRoot) ?? "HEAD"
        let statuses = await runGitStatus(in: repoRoot)
        return GitWorkspaceSummary(branch: branch, changedCount: statuses.count)
    }

    private func currentBranch(in repoRoot: URL) async -> String? {
        do {
            let result = try await ProcessRunner.run(
                executable: "git",
                arguments: GitCommand.arguments(["-C", repoRoot.path, "rev-parse", "--abbrev-ref", "HEAD"]),
                timeout: 5
            )
            guard result.exitCode == 0 else { return nil }
            let branch = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return branch.isEmpty ? nil : branch
        } catch {
            return nil
        }
    }

    public func status(for directory: URL) async -> GitStatusSnapshot {
        let workingDirectory = resolvedDirectory(for: directory)

        guard let repoRoot = await repoRoot(for: workingDirectory) else {
            return .empty
        }

        let statuses = await runGitStatus(in: repoRoot)
        return GitStatusSnapshot(repoRoot: repoRoot.path, statuses: statuses)
    }

    private func resolvedDirectory(for url: URL) -> URL {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return url
        }
        return url.deletingLastPathComponent()
    }

    private func repoRoot(for directory: URL) async -> URL? {
        do {
            let result = try await ProcessRunner.run(
                executable: "git",
                arguments: GitCommand.arguments(["-C", directory.path, "rev-parse", "--show-toplevel"]),
                timeout: 5
            )
            guard result.exitCode == 0 else { return nil }
            let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { return nil }
            return URL(fileURLWithPath: path)
        } catch {
            return nil
        }
    }

    private func runGitStatus(in repoRoot: URL) async -> [String: GitFileStatus] {
        do {
            let result = try await ProcessRunner.run(
                executable: "git",
                arguments: GitCommand.arguments(["-C", repoRoot.path, "status", "--porcelain", "-uall"]),
                timeout: 10
            )
            guard result.exitCode == 0 else { return [:] }
            return Self.parseGitStatus(result.stdout, repoRoot: repoRoot)
        } catch {
            return [:]
        }
    }

    public nonisolated static func parseGitStatus(_ output: String, repoRoot: URL) -> [String: GitFileStatus] {
        var statuses: [String: GitFileStatus] = [:]

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            guard line.count >= 3 else { continue }

            let indexChar = line[line.startIndex]
            let workTreeChar = line[line.index(after: line.startIndex)]
            var path = String(line.dropFirst(3))

            if let arrowRange = path.range(of: " -> ") {
                path = String(path[arrowRange.upperBound...])
            }
            if path.hasPrefix("\""), path.hasSuffix("\"") {
                path = String(path.dropFirst().dropLast())
            }

            let status = determineStatus(index: indexChar, workTree: workTreeChar)
            guard status != .clean else { continue }

            let fileURL = repoRoot.appendingPathComponent(path).standardizedFileURL
            statuses[fileURL.path] = status
        }

        return statuses
    }

    private nonisolated static func determineStatus(index: Character, workTree: Character) -> GitFileStatus {
        if index == "?", workTree == "?" {
            return .untracked
        }

        if index == "U" || workTree == "U" ||
            (index == "A" && workTree == "A") ||
            (index == "D" && workTree == "D") {
            return .conflict
        }

        if index != " ", index != "?" {
            return workTree == " " ? .staged : .modified
        }

        if workTree == "M" || workTree == "D" {
            return .modified
        }

        return .clean
    }
}

import Foundation

/// Helper class for creating temporary Git repositories in tests
class GitTestHelper {
    let rootDirectory: URL

    init() {
        rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitTestHelper-\(UUID().uuidString)")
    }

    /// Sets up the test environment by creating the root directory
    func setUp() throws {
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
    }

    /// Cleans up by removing the root directory and all contents
    func tearDown() {
        try? FileManager.default.removeItem(at: rootDirectory)
    }

    /// Creates a new Git repository in a subdirectory
    /// - Parameter name: Name of the directory to create
    /// - Returns: URL of the created repository
    @discardableResult
    func createRepo(named name: String) throws -> URL {
        let repoURL = rootDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        try runGit(["init"], in: repoURL)
        // Configure user for commits
        try runGit(["config", "user.email", "test@test.com"], in: repoURL)
        try runGit(["config", "user.name", "Test User"], in: repoURL)
        return repoURL
    }

    /// Creates a file in the specified directory
    /// - Parameters:
    ///   - name: Name of the file
    ///   - content: Content to write
    ///   - directory: Directory to create the file in
    /// - Returns: URL of the created file
    @discardableResult
    func createFile(named name: String, content: String, in directory: URL) throws -> URL {
        let fileURL = directory.appendingPathComponent(name)
        // Create parent directories if needed
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    /// Creates a subdirectory
    /// - Parameters:
    ///   - name: Name of the subdirectory (can include path components like "docs/api")
    ///   - parent: Parent directory
    /// - Returns: URL of the created directory
    @discardableResult
    func createDirectory(named name: String, in parent: URL) throws -> URL {
        let dirURL = parent.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        return dirURL
    }

    /// Stages and commits all changes in a repository
    /// - Parameters:
    ///   - message: Commit message
    ///   - repoURL: URL of the repository
    func commit(message: String, in repoURL: URL) throws {
        try runGit(["add", "-A"], in: repoURL)
        try runGit(["commit", "-m", message], in: repoURL)
    }

    /// Adds a submodule to a repository
    /// - Parameters:
    ///   - submoduleURL: URL of the repository to add as submodule
    ///   - path: Path within the parent repo where submodule should be added
    ///   - parentURL: URL of the parent repository
    func addSubmodule(_ submoduleURL: URL, at path: String, in parentURL: URL) throws {
        // Allow file:// protocol for local submodules (required by recent git versions)
        try runGit(["-c", "protocol.file.allow=always", "submodule", "add", submoduleURL.path, path], in: parentURL)
    }

    /// Creates a worktree for a repository
    /// - Parameters:
    ///   - name: Name for the worktree directory
    ///   - branch: Branch name to checkout in the worktree
    ///   - repoURL: URL of the main repository
    /// - Returns: URL of the created worktree
    @discardableResult
    func createWorktree(named name: String, branch: String, in repoURL: URL) throws -> URL {
        let worktreeURL = rootDirectory.appendingPathComponent(name)
        try runGit(["worktree", "add", "-b", branch, worktreeURL.path], in: repoURL)
        return worktreeURL
    }

    /// Runs a git command in the specified directory
    private func runGit(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "GitTestHelper",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "git \(arguments.joined(separator: " ")) failed"]
            )
        }
    }
}

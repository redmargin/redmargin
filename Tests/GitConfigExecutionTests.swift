import XCTest
@testable import RedmarginCore

/// Opening a file or folder makes Redmargin inspect its repository immediately,
/// with no user action. Git honours config from the repository being inspected,
/// and `core.fsmonitor`, `diff.external`, and `diff.*.textconv` all name commands
/// for Git to run. A repository cloned from anywhere must not be able to execute
/// code simply by being viewed.
final class GitConfigExecutionTests: XCTestCase {
    private var repoDir: URL!
    private var markerDir: URL!

    override func setUp() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rm-gitexec-\(UUID().uuidString.prefix(8))")
        repoDir = root.appendingPathComponent("repo")
        markerDir = root.appendingPathComponent("markers")
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: markerDir, withIntermediateDirectories: true)

        try await git(["init"])
        try await git(["config", "user.email", "test@example.com"])
        try await git(["config", "user.name", "Test"])
        try "line one\nline two\n".write(to: documentURL, atomically: true, encoding: .utf8)
        try await git(["add", "doc.md"])
        try await git(["commit", "-m", "initial"])
        // A working-tree change, so `git diff` has something to filter.
        try "line one\nline changed\n".write(to: documentURL, atomically: true, encoding: .utf8)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: repoDir.deletingLastPathComponent())
    }

    private var documentURL: URL { repoDir.appendingPathComponent("doc.md") }

    @discardableResult
    private func git(_ arguments: [String]) async throws -> ProcessResult {
        try await ProcessRunner.run(executable: "git", arguments: arguments, workingDirectory: repoDir, timeout: 15)
    }

    /// A config value that drops a file on disk when Git executes it.
    private func payload(_ name: String) -> String {
        "touch \(markerDir.appendingPathComponent(name).path)"
    }

    private func markerExists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: markerDir.appendingPathComponent(name).path)
    }

    /// `git status` refreshes the index, which runs `core.fsmonitor` as a hook.
    func testStatusDoesNotRunFsmonitorCommand() async throws {
        try await git(["config", "core.fsmonitor", "\(payload("fsmonitor")); false"])

        _ = await GitStatusProvider().status(for: repoDir)

        XCTAssertFalse(markerExists("fsmonitor"), "Opening a repository executed its core.fsmonitor command")
    }

    /// `diff.external` replaces Git's diff engine with an arbitrary command.
    func testDiffDoesNotRunExternalDiffCommand() async throws {
        try await git(["config", "diff.external", "\(payload("extdiff")); true"])

        _ = try await GitDiffParser.parseChanges(forFile: documentURL, repoRoot: repoDir)

        XCTAssertFalse(markerExists("extdiff"), "Diffing a file executed its diff.external command")
    }

    /// `diff.<driver>.textconv`, selected by .gitattributes, is a separate vector
    /// from `diff.external` and is only refused by `--no-textconv`. Configured on
    /// its own here so `diff.external` cannot mask it.
    func testDiffDoesNotRunTextconvCommand() async throws {
        try "*.md diff=evil\n".write(
            to: repoDir.appendingPathComponent(".gitattributes"),
            atomically: true,
            encoding: .utf8
        )
        try await git(["config", "diff.evil.textconv", "\(payload("textconv")); cat"])

        _ = try await GitDiffParser.parseChanges(forFile: documentURL, repoRoot: repoDir)

        XCTAssertFalse(markerExists("textconv"), "Diffing a file executed its diff.textconv command")
    }

    /// The hardening must not cost correctness: a real change is still reported.
    func testHardenedDiffStillDetectsChanges() async throws {
        try await git(["config", "core.fsmonitor", "\(payload("fsmonitor")); false"])
        try await git(["config", "diff.external", "\(payload("extdiff")); true"])

        let changes = try await GitDiffParser.parseChanges(forFile: documentURL, repoRoot: repoDir)

        XCTAssertFalse(changes.modifiedRanges.isEmpty, "Hardened diff stopped reporting a real modification")
    }

    /// And status still classifies a modified file.
    func testHardenedStatusStillReportsModifiedFile() async throws {
        try await git(["config", "core.fsmonitor", "\(payload("fsmonitor")); false"])

        let snapshot = await GitStatusProvider().status(for: repoDir)

        XCTAssertEqual(snapshot.statuses[documentURL.standardizedFileURL.path], .modified)
    }
}

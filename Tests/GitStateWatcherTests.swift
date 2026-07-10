import XCTest
import Foundation
@testable import RedmarginCore

/// Covers `GitRepoWatcher` (`src/Core/FileProvider/LocalFileProvider.swift:76`), which
/// tells the gutter to refresh when the repository moves underneath the open document.
/// It watches `.git/index`, `.git/HEAD`, and whichever branch ref HEAD points at,
/// re-pointing that last watcher whenever HEAD changes.
final class GitStateWatcherTests: XCTestCase {

    private var helper: GitTestHelper!
    private var repoURL: URL!

    /// The watcher's `onChange` is fixed at construction, so route it through a box
    /// the test can re-target between phases.
    private let handlerLock = NSLock()
    private var changeHandler: (() -> Void)?

    private func setHandler(_ handler: (() -> Void)?) {
        handlerLock.lock()
        changeHandler = handler
        handlerLock.unlock()
    }

    private func fireHandler() {
        handlerLock.lock()
        let handler = changeHandler
        handlerLock.unlock()
        handler?()
    }

    override func setUpWithError() throws {
        helper = GitTestHelper()
        try helper.setUp()
        repoURL = try helper.createRepo(named: "repo")
        try helper.createFile(named: "note.md", content: "# Note\n", in: repoURL)
        try helper.commit(message: "initial", in: repoURL)
    }

    override func tearDownWithError() throws {
        setHandler(nil)
        helper.tearDown()
    }

    private var gitDir: URL { repoURL.appendingPathComponent(".git") }

    /// Builds the watcher and gives its file sources a moment to arm.
    private func makeWatcher() -> GitRepoWatcher {
        let watcher = GitRepoWatcher(repoRoot: repoURL.path) { [weak self] in
            self?.fireHandler()
        }
        Thread.sleep(forTimeInterval: 0.15)
        return watcher
    }

    /// An expectation that survives the watcher firing more than once, which the
    /// underlying file sources are free to do for a single write.
    private func changeExpectation(_ description: String) -> XCTestExpectation {
        let expectation = expectation(description: description)
        expectation.assertForOverFulfill = false
        setHandler { expectation.fulfill() }
        return expectation
    }

    private func currentBranchRef() throws -> String {
        let head = try String(contentsOf: gitDir.appendingPathComponent("HEAD"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(head.hasPrefix("ref: "), "A fresh repo should be on a branch, got \(head)")
        return String(head.dropFirst(5))
    }

    private func overwrite(_ url: URL, with contents: String) throws {
        try contents.write(to: url, atomically: false, encoding: .utf8)
    }

    /// Staging a file rewrites `.git/index`. Without the index watcher, nothing fires.
    func testWatcherReportsIndexChange() throws {
        let watcher = makeWatcher()
        let changed = changeExpectation("onChange fired for index")

        let index = gitDir.appendingPathComponent("index")
        try Data(contentsOf: index).write(to: index)

        wait(for: [changed], timeout: 5)
        XCTAssertNotNil(watcher)
    }

    /// A branch switch rewrites HEAD.
    func testWatcherReportsHeadChange() throws {
        let watcher = makeWatcher()
        let changed = changeExpectation("onChange fired for HEAD")

        try overwrite(gitDir.appendingPathComponent("HEAD"), with: "ref: refs/heads/feature\n")

        wait(for: [changed], timeout: 5)
        XCTAssertNotNil(watcher)
    }

    /// A commit on the current branch rewrites `refs/heads/<branch>`.
    func testWatcherReportsBranchRefChange() throws {
        let ref = try currentBranchRef()
        let watcher = makeWatcher()
        let changed = changeExpectation("onChange fired for branch ref")

        try overwrite(gitDir.appendingPathComponent(ref), with: String(repeating: "0", count: 40) + "\n")

        wait(for: [changed], timeout: 5)
        XCTAssertNotNil(watcher)
    }

    /// After HEAD moves to another branch the watcher must follow it, so writes to the
    /// new ref are reported. This is what `updateRefWatcher` exists for, and what a
    /// watcher that only ever watched the original ref would miss.
    func testWatcherFollowsHeadOntoTheNewBranchRef() throws {
        let newRef = "refs/heads/feature"
        let newRefURL = gitDir.appendingPathComponent(newRef)
        try FileManager.default.createDirectory(
            at: newRefURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try overwrite(newRefURL, with: String(repeating: "1", count: 40) + "\n")

        let watcher = makeWatcher()

        let headSeen = changeExpectation("onChange fired for HEAD")
        try overwrite(gitDir.appendingPathComponent("HEAD"), with: "ref: \(newRef)\n")
        wait(for: [headSeen], timeout: 5)

        // The watcher has re-pointed at refs/heads/feature; writing it must report.
        Thread.sleep(forTimeInterval: 0.2)
        let refSeen = changeExpectation("onChange fired for the new branch ref")
        try overwrite(newRefURL, with: String(repeating: "2", count: 40) + "\n")

        wait(for: [refSeen], timeout: 5)
        XCTAssertNotNil(watcher)
    }

    /// A detached HEAD names a commit, not a ref, so there is no branch ref to follow.
    /// The watcher must report the HEAD write and survive having nothing to re-point at.
    func testDetachedHeadIsReportedAndLeavesTheWatcherAlive() throws {
        let watcher = makeWatcher()

        let headSeen = changeExpectation("onChange fired for detached HEAD")
        try overwrite(gitDir.appendingPathComponent("HEAD"), with: String(repeating: "3", count: 40) + "\n")
        wait(for: [headSeen], timeout: 5)

        // Still watching HEAD: a second write is reported too.
        Thread.sleep(forTimeInterval: 0.2)
        let secondSeen = changeExpectation("onChange fired for the next HEAD write")
        try overwrite(gitDir.appendingPathComponent("HEAD"), with: "ref: refs/heads/main\n")

        wait(for: [secondSeen], timeout: 5)
        XCTAssertNotNil(watcher, "A detached HEAD must not tear the watcher down")
    }
}

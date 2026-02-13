import XCTest
import Observation
@testable import Redmargin
@testable import RedmarginCore

@MainActor
final class DocumentStateTests: XCTestCase {

    var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocumentStateTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    // MARK: - Reload Content

    func testReloadContentUpdatesContent() async throws {
        let testFile = tempDir.appendingPathComponent("test.md")
        let initial = "# Initial Content"
        try initial.write(to: testFile, atomically: true, encoding: .utf8)

        let state = DocumentState(content: initial, fileURL: testFile)
        XCTAssertEqual(state.content, initial)

        // Wait for file watcher to set up
        try await Task.sleep(nanoseconds: 200_000_000)

        // Modify file externally (atomic write triggers rename → watcher restart → onChange)
        let updated = "# Updated Content"
        try updated.write(to: testFile, atomically: true, encoding: .utf8)

        // File watcher restart has retry delay (0.1s), then reloadContent reads file
        // Give it up to 3 seconds to propagate
        let deadline = Date().addingTimeInterval(3.0)
        while state.content != updated {
            if Date() > deadline {
                XCTFail("Content was not updated within timeout. Still: \(state.content)")
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms poll
        }

        XCTAssertEqual(state.content, updated)
    }

    // MARK: - Refresh

    func testRefreshIncrementsToken() async throws {
        let testFile = tempDir.appendingPathComponent("refresh.md")
        let initial = "# Before Refresh"
        try initial.write(to: testFile, atomically: true, encoding: .utf8)

        let state = DocumentState(content: initial, fileURL: testFile)
        XCTAssertEqual(state.refreshToken, 0)

        // Change file content on disk
        let updated = "# After Refresh"
        try updated.write(to: testFile, atomically: true, encoding: .utf8)

        // Call refresh
        state.refresh()

        // Wait for refresh to complete (isRefreshing goes true then false after 0.3s)
        let deadline = Date().addingTimeInterval(3.0)
        // First wait for isRefreshing to become true
        while !state.isRefreshing {
            if Date() > deadline {
                XCTFail("refresh() never set isRefreshing to true")
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        // Then wait for it to finish
        while state.isRefreshing {
            if Date() > deadline {
                XCTFail("Refresh did not complete within timeout")
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertEqual(state.refreshToken, 1, "refreshToken should increment on refresh")
        XCTAssertEqual(state.content, updated, "Content should be re-read from disk")
    }

    // MARK: - Load File

    func testLoadFileUpdatesAllState() async throws {
        let file1 = tempDir.appendingPathComponent("file1.md")
        let file2 = tempDir.appendingPathComponent("file2.md")
        let content1 = "# File One"
        let content2 = "# File Two"
        try content1.write(to: file1, atomically: true, encoding: .utf8)
        try content2.write(to: file2, atomically: true, encoding: .utf8)

        let state = DocumentState(content: content1, fileURL: file1)
        XCTAssertEqual(state.fileURL, file1)
        XCTAssertEqual(state.content, content1)
        let initialToken = state.refreshToken

        // Wait for init's background Task to finish (file watcher setup + git detection)
        try await Task.sleep(nanoseconds: 500_000_000)

        // Load second file
        try await state.loadFile(at: file2)

        XCTAssertEqual(state.fileURL, file2, "fileURL should point to new file")
        XCTAssertEqual(state.content, content2, "content should match new file")
        XCTAssertEqual(state.refreshToken, initialToken + 1, "refreshToken should increment")
        XCTAssertNil(state.gitChanges, "gitChanges should be cleared when loading new file")
    }
}

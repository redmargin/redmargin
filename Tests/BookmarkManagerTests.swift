import XCTest
@testable import RedmarginLib

final class BookmarkManagerTests: XCTestCase {
    private let testBookmarksKey = "RedMargin.SecurityScopedBookmarks"
    private var tempFileURL: URL?

    override func setUp() {
        super.setUp()
        // Clear any existing bookmarks
        UserDefaults.standard.removeObject(forKey: testBookmarksKey)
    }

    override func tearDown() {
        // Clean up temp file
        if let url = tempFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        // Clean up UserDefaults
        UserDefaults.standard.removeObject(forKey: testBookmarksKey)
        BookmarkManager.shared.stopAccessingAll()
        super.tearDown()
    }

    private func createTempFile() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test-\(UUID().uuidString).md")
        try? "# Test".write(to: fileURL, atomically: true, encoding: .utf8)
        tempFileURL = fileURL
        return fileURL
    }

    func testCreatesBookmark() {
        let url = createTempFile()

        BookmarkManager.shared.createBookmark(for: url)

        // Verify bookmark was stored
        let bookmarks = UserDefaults.standard.dictionary(forKey: testBookmarksKey) as? [String: Data] ?? [:]
        XCTAssertNotNil(bookmarks[url.path], "Bookmark should be created for file")
        XCTAssertFalse(bookmarks[url.path]!.isEmpty, "Bookmark data should not be empty")
    }

    func testResolvesBookmark() {
        let url = createTempFile()

        // Create bookmark
        BookmarkManager.shared.createBookmark(for: url)

        // Resolve it
        let resolvedURL = BookmarkManager.shared.resolveBookmark(for: url)

        XCTAssertNotNil(resolvedURL, "Resolved URL should not be nil")
        // Compare standardized paths to handle /var vs /private/var symlink
        XCTAssertEqual(
            resolvedURL?.standardizedFileURL.path,
            url.standardizedFileURL.path,
            "Resolved URL should match original path"
        )
    }

    func testHandlesStaleBookmark() {
        let url = createTempFile()

        // Create bookmark
        BookmarkManager.shared.createBookmark(for: url)

        // Delete the file
        try? FileManager.default.removeItem(at: url)
        tempFileURL = nil

        // Try to resolve - should fail gracefully
        let resolvedURL = BookmarkManager.shared.resolveBookmark(for: url)

        // Note: Bookmark resolution may still succeed for recently deleted files
        // The important thing is it doesn't crash
        if resolvedURL == nil {
            // Verify bookmark was cleaned up
            let bookmarks = UserDefaults.standard.dictionary(forKey: testBookmarksKey) as? [String: Data] ?? [:]
            XCTAssertNil(bookmarks[url.path], "Stale bookmark should be removed")
        }
    }

    func testStartAccessingResource() {
        let url = createTempFile()

        BookmarkManager.shared.createBookmark(for: url)

        if let resolvedURL = BookmarkManager.shared.resolveBookmark(for: url) {
            let success = BookmarkManager.shared.startAccessing(resolvedURL)
            // Note: startAccessingSecurityScopedResource returns false when not sandboxed
            // but the app should still work
            XCTAssertTrue(success || !isSandboxed(), "Should start accessing or not be sandboxed")

            BookmarkManager.shared.stopAccessing(resolvedURL)
        }
    }

    func testStopAccessingAll() {
        let url1 = createTempFile()
        let tempDir = FileManager.default.temporaryDirectory
        let url2 = tempDir.appendingPathComponent("test2-\(UUID().uuidString).md")
        try? "# Test 2".write(to: url2, atomically: true, encoding: .utf8)

        BookmarkManager.shared.createBookmark(for: url1)
        BookmarkManager.shared.createBookmark(for: url2)

        if let resolved1 = BookmarkManager.shared.resolveBookmark(for: url1) {
            BookmarkManager.shared.startAccessing(resolved1)
        }
        if let resolved2 = BookmarkManager.shared.resolveBookmark(for: url2) {
            BookmarkManager.shared.startAccessing(resolved2)
        }

        // Should not crash
        BookmarkManager.shared.stopAccessingAll()

        // Cleanup
        try? FileManager.default.removeItem(at: url2)
    }

    func testCleanupStaleBookmarks() {
        // Create a temp file and bookmark it
        let url = createTempFile()
        BookmarkManager.shared.createBookmark(for: url)

        // Delete the file
        try? FileManager.default.removeItem(at: url)
        tempFileURL = nil

        // Run cleanup
        BookmarkManager.shared.cleanupStaleBookmarks()

        // Verify bookmark was removed
        let bookmarks = UserDefaults.standard.dictionary(forKey: testBookmarksKey) as? [String: Data] ?? [:]
        XCTAssertNil(bookmarks[url.path], "Stale bookmark should be cleaned up")
    }

    func testRemoveBookmark() {
        let url = createTempFile()

        BookmarkManager.shared.createBookmark(for: url)

        // Verify bookmark exists
        var bookmarks = UserDefaults.standard.dictionary(forKey: testBookmarksKey) as? [String: Data] ?? [:]
        XCTAssertNotNil(bookmarks[url.path], "Bookmark should exist")

        // Remove it
        BookmarkManager.shared.removeBookmark(for: url)

        // Verify it's gone
        bookmarks = UserDefaults.standard.dictionary(forKey: testBookmarksKey) as? [String: Data] ?? [:]
        XCTAssertNil(bookmarks[url.path], "Bookmark should be removed")
    }

    private func isSandboxed() -> Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }
}

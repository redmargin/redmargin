import Foundation

/// Manages security-scoped bookmarks for sandboxed file access
public class BookmarkManager {
    public static let shared = BookmarkManager()

    private let bookmarksKey = "RedMargin.SecurityScopedBookmarks"
    private var activeAccess: [URL: Bool] = [:]

    private init() {}

    // MARK: - Bookmark Creation

    /// Creates a security-scoped bookmark for a file URL
    public func createBookmark(for url: URL) {
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            saveBookmarkData(bookmarkData, for: url)
        } catch {
            print("Failed to create bookmark for \(url.path): \(error)")
        }
    }

    // MARK: - Bookmark Resolution

    /// Resolves a bookmark to get a valid URL with security scope
    /// Returns nil if bookmark doesn't exist or resolution fails
    public func resolveBookmark(for originalURL: URL) -> URL? {
        guard let bookmarkData = loadBookmarkData(for: originalURL) else {
            return nil
        }

        do {
            var isStale = false
            let resolvedURL = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                // Bookmark is stale, try to recreate it
                createBookmark(for: resolvedURL)
            }

            return resolvedURL
        } catch {
            print("Failed to resolve bookmark for \(originalURL.path): \(error)")
            removeBookmark(for: originalURL)
            return nil
        }
    }

    // MARK: - Security-Scoped Access

    /// Starts accessing a security-scoped resource
    /// Returns true if access was granted
    @discardableResult
    public func startAccessing(_ url: URL) -> Bool {
        if activeAccess[url] == true {
            return true
        }

        let success = url.startAccessingSecurityScopedResource()
        if success {
            activeAccess[url] = true
        }
        return success
    }

    /// Stops accessing a security-scoped resource
    public func stopAccessing(_ url: URL) {
        if activeAccess[url] == true {
            url.stopAccessingSecurityScopedResource()
            activeAccess[url] = nil
        }
    }

    /// Stops accessing all security-scoped resources
    public func stopAccessingAll() {
        for (url, isActive) in activeAccess where isActive {
            url.stopAccessingSecurityScopedResource()
        }
        activeAccess.removeAll()
    }

    // MARK: - Bookmark Storage

    private func saveBookmarkData(_ data: Data, for url: URL) {
        var bookmarks = loadAllBookmarks()
        bookmarks[url.path] = data
        UserDefaults.standard.set(bookmarks, forKey: bookmarksKey)
    }

    private func loadBookmarkData(for url: URL) -> Data? {
        let bookmarks = loadAllBookmarks()
        return bookmarks[url.path]
    }

    private func loadAllBookmarks() -> [String: Data] {
        UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: Data] ?? [:]
    }

    /// Removes a bookmark for a specific URL
    public func removeBookmark(for url: URL) {
        var bookmarks = loadAllBookmarks()
        bookmarks.removeValue(forKey: url.path)
        UserDefaults.standard.set(bookmarks, forKey: bookmarksKey)
    }

    /// Removes all stored bookmarks
    public func clearAllBookmarks() {
        UserDefaults.standard.removeObject(forKey: bookmarksKey)
        stopAccessingAll()
    }

    // MARK: - Cleanup

    /// Removes bookmarks for files that no longer exist
    public func cleanupStaleBookmarks() {
        var bookmarks = loadAllBookmarks()
        let staleKeys = bookmarks.keys.filter { path in
            !FileManager.default.fileExists(atPath: path)
        }

        for key in staleKeys {
            bookmarks.removeValue(forKey: key)
        }

        if !staleKeys.isEmpty {
            UserDefaults.standard.set(bookmarks, forKey: bookmarksKey)
        }
    }
}

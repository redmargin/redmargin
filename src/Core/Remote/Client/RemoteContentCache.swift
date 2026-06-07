import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Local, best-effort cache of the last-seen contents of remote documents.
///
/// Restoring a remote window reads from this cache so the window can appear
/// instantly with its last-seen contents, before (or without) a live connection.
/// Writes are fire-and-forget: failures never surface to the UI.
///
/// One file is stored per location, named by a stable SHA-256 of the location's
/// `storageKey`. Oversized content is skipped and the number of entries is bounded,
/// evicting the least-recently-written file when the cap is exceeded.
public actor RemoteContentCache {
    public static let shared = RemoteContentCache()

    private let baseDirectory: URL
    private let maxContentBytes: Int
    private let maxEntries: Int
    private let fileManager = FileManager.default

    /// - Parameters:
    ///   - baseDirectory: Where cache files live. Defaults to
    ///     `Application Support/Redmargin/RemoteContentCache`. Injectable so tests
    ///     can use a temp directory.
    ///   - maxContentBytes: Content larger than this is not cached (default 4 MB).
    ///   - maxEntries: At most this many cached files are kept (default 200);
    ///     the least-recently-written file is evicted past the cap.
    public init(
        baseDirectory: URL? = nil,
        maxContentBytes: Int = 4 * 1024 * 1024,
        maxEntries: Int = 200
    ) {
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            let appSupport = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.baseDirectory = appSupport
                .appendingPathComponent("Redmargin", isDirectory: true)
                .appendingPathComponent("RemoteContentCache", isDirectory: true)
        }
        self.maxContentBytes = maxContentBytes
        self.maxEntries = maxEntries
    }

    /// Persist `content` for `location`. Skips content above the size cap and
    /// enforces the entry cap afterwards. Best-effort: errors are swallowed.
    public func save(_ content: String, for location: RemoteLocation) {
        guard content.utf8.count <= maxContentBytes else { return }
        do {
            try ensureDirectory()
            try Data(content.utf8).write(to: fileURL(for: location), options: .atomic)
            enforceEntryCap()
        } catch {
            // Cache is best-effort; never surface a write failure.
        }
    }

    /// Returns the cached content for `location`, or nil if nothing is cached.
    public func load(for location: RemoteLocation) -> String? {
        loadSync(for: location)
    }

    /// Synchronous, non-isolated read of the cached content. A plain file read with
    /// no shared mutable state, so restore can pull cached content for each window
    /// without awaiting the actor (keeping window creation off the network entirely).
    public nonisolated func loadSync(for location: RemoteLocation) -> String? {
        guard let data = try? Data(contentsOf: fileURL(for: location)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Deletes the cached entry for `location` if present.
    public func evict(for location: RemoteLocation) {
        try? fileManager.removeItem(at: fileURL(for: location))
    }

    // MARK: - Internals

    private func ensureDirectory() throws {
        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }

    private nonisolated func fileURL(for location: RemoteLocation) -> URL {
        baseDirectory.appendingPathComponent(Self.stableHash(location.storageKey))
    }

    /// Evicts least-recently-written files until at most `maxEntries` remain.
    private func enforceEntryCap() {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return }

        guard entries.count > maxEntries else { return }

        let sorted = entries.sorted { lhs, rhs in
            modificationDate(of: lhs) < modificationDate(of: rhs)
        }
        for url in sorted.prefix(entries.count - maxEntries) {
            try? fileManager.removeItem(at: url)
        }
    }

    private func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
    }

    /// Stable, filesystem-safe hex digest of a location's storage key.
    /// Uses SHA-256 where CryptoKit is available (the only platform the cache
    /// runs on); falls back to a deterministic FNV-1a digest so `RedmarginCore`
    /// still compiles on Linux, where the cache is never exercised.
    static func stableHash(_ string: String) -> String {
        let data = Data(string.utf8)
        #if canImport(CryptoKit)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #else
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        return String(format: "%016x", hash)
        #endif
    }
}

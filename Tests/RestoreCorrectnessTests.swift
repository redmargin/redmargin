import XCTest
@testable import Redmargin
@testable import RedmarginCore

/// What the app must still know about after a crash, a force-quit, or an offline
/// launch.
final class RestoreCorrectnessTests: WindowlessTestCase {

    // MARK: - Window identity

    /// The regression: identities were joined with colons and parsed at the first
    /// one, so an IPv6 host came back truncated with the rest of the address glued
    /// onto the front of the path.
    func testIPv6RemoteIdentityRoundTrips() throws {
        let location = RemoteLocation(host: "fe80::1ff:fe23:4567:890a", path: "/srv/notes/plan.md")
        let encoded = try XCTUnwrap(PersistedWindowIdentity.remote(location).encoded)

        let decoded = try XCTUnwrap(PersistedWindowIdentity.decode(encoded))

        XCTAssertEqual(decoded, .remote(location))
        XCTAssertEqual(decoded.remoteLocation?.host, "fe80::1ff:fe23:4567:890a")
        XCTAssertEqual(decoded.remoteLocation?.path, "/srv/notes/plan.md")
    }

    func testOrdinaryRemoteIdentityRoundTrips() throws {
        let location = RemoteLocation(host: "devtest", path: "/tmp/notes.md")
        let encoded = try XCTUnwrap(PersistedWindowIdentity.remote(location).encoded)
        XCTAssertEqual(PersistedWindowIdentity.decode(encoded), .remote(location))
    }

    func testLocalAndFolderIdentitiesRoundTrip() throws {
        let local = PersistedWindowIdentity.local(path: "/Users/x/a: b.md")
        let folder = PersistedWindowIdentity.folder(path: "/Users/x/notes")

        XCTAssertEqual(PersistedWindowIdentity.decode(try XCTUnwrap(local.encoded)), local)
        XCTAssertEqual(PersistedWindowIdentity.decode(try XCTUnwrap(folder.encoded)), folder)
    }

    /// Identities written by an older build must still restore their windows.
    func testLegacyIdentitiesStillDecode() {
        XCTAssertEqual(
            PersistedWindowIdentity.decode("remote:devtest:/tmp/notes.md"),
            .remote(RemoteLocation(host: "devtest", path: "/tmp/notes.md"))
        )
        XCTAssertEqual(
            PersistedWindowIdentity.decode("folder:/Users/x/notes"),
            .folder(path: "/Users/x/notes")
        )
        XCTAssertEqual(
            PersistedWindowIdentity.decode("/Users/x/notes.md"),
            .local(path: "/Users/x/notes.md")
        )
    }

    /// Why the format had to change: the legacy colon-joined form cannot represent
    /// an IPv6 host at all. Reading one back truncates the host at its first colon
    /// and prepends the remainder to the path, which matches no open window. The
    /// legacy reader reproduces that faithfully; only the new form round-trips.
    func testLegacyFormatCannotRepresentAnIPv6Host() throws {
        let decoded = try XCTUnwrap(PersistedWindowIdentity.decode("remote:fe80::1:/srv/plan.md"))

        XCTAssertEqual(decoded.remoteLocation?.host, "fe80")
        XCTAssertEqual(decoded.remoteLocation?.path, ":1:/srv/plan.md")

        let location = RemoteLocation(host: "fe80::1", path: "/srv/plan.md")
        let modern = try XCTUnwrap(PersistedWindowIdentity.remote(location).encoded)
        XCTAssertEqual(PersistedWindowIdentity.decode(modern)?.remoteLocation, location)
    }

    /// A folder location is identified by its trailing separator, not by whether
    /// the content happens to be empty.
    func testFolderLocationsAreIdentifiedByTrailingSeparator() {
        XCTAssertTrue(RemoteLocation(host: "devtest", path: "/srv/notes/").isFolder)
        XCTAssertFalse(RemoteLocation(host: "devtest", path: "/srv/notes.md").isFolder)
        XCTAssertFalse(RemoteLocation(host: "devtest", path: "/srv/empty.md").isFolder)
    }
}

/// What `RemoteDocumentState` writes into the offline cache.
@MainActor
final class RemoteCacheWriteTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoteCacheWriteTests-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func makeState(
        remote: FakeRemoteHost,
        location: RemoteLocation,
        content: String,
        cache: RemoteContentCache
    ) -> RemoteDocumentState {
        RemoteDocumentState(
            content: content,
            location: location,
            fileProvider: RemoteFileProvider(connection: remote.connection),
            connectsOnDemand: true,
            contentCache: cache
        )
    }

    /// `cacheContent` writes on a detached task; wait for it to land.
    private func awaitCache(
        _ cache: RemoteContentCache,
        for location: RemoteLocation,
        toEqual expected: String?,
        timeout: TimeInterval = 2
    ) async -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        var latest: String?
        while Date() < deadline {
            latest = await cache.load(for: location)
            if latest == expected { return latest }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return latest
    }

    /// The regression: `cacheContent` skipped every empty string, so a file emptied
    /// on the server kept its old bytes and an offline restore showed content the
    /// file no longer had.
    func testEmptiedRemoteFileIsCachedAsEmpty() async throws {
        let remote = await FakeRemoteHost()
        defer { remote.stop() }

        let cache = RemoteContentCache(baseDirectory: directory)
        let location = RemoteLocation(host: "harness.invalid", path: "/remote/notes.md")
        let state = makeState(remote: remote, location: location, content: "# Had content\n", cache: cache)

        state.cacheContent("# Had content\n")
        let seeded = await awaitCache(cache, for: location, toEqual: "# Had content\n")
        XCTAssertEqual(seeded, "# Had content\n")

        state.cacheContent("")

        let afterEmptying = await awaitCache(cache, for: location, toEqual: "")
        XCTAssertEqual(afterEmptying, "", "An emptied file kept its stale cached content")
    }

    /// A folder window has no document content, and must not create a cache entry.
    func testFolderWindowContentIsNotCached() async throws {
        let remote = await FakeRemoteHost()
        defer { remote.stop() }

        let cache = RemoteContentCache(baseDirectory: directory)
        let folder = RemoteLocation(host: "harness.invalid", path: "/remote/notes/")
        let state = makeState(remote: remote, location: folder, content: "", cache: cache)

        state.cacheContent("")
        try await Task.sleep(nanoseconds: 300_000_000)

        let cached = await cache.load(for: folder)
        XCTAssertNil(cached, "A folder window created a cache entry")
    }
}

/// The open-folder snapshot must survive a launch that never reaches a clean
/// termination.
@MainActor
final class FolderSnapshotPersistenceTests: XCTestCase {
    private let key = "RedMargin.OpenFolderURLs"
    private var saved: [String]?

    override func setUp() {
        super.setUp()
        saved = UserDefaults.standard.stringArray(forKey: key)
    }

    override func tearDown() {
        if let saved {
            UserDefaults.standard.set(saved, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
        super.tearDown()
    }

    /// The regression: restore consumed the snapshot during launch. A crash before
    /// clean termination then left nothing to reopen.
    func testRestoringFoldersLeavesTheSnapshotInPlace() throws {
        let paths = ["/tmp/folder-a", "/tmp/folder-b"]
        UserDefaults.standard.set(paths, forKey: key)

        let appDelegate = AppDelegate()
        _ = appDelegate.restoreSavedFolderURLs()

        XCTAssertEqual(
            UserDefaults.standard.stringArray(forKey: key),
            paths,
            "Restoring folders consumed the snapshot, so a crash would lose them"
        )
    }

    /// And the snapshot tracks the live windows rather than only being written at
    /// termination.
    func testSnapshotIsRewrittenFromLiveFolderWindows() {
        UserDefaults.standard.set(["/tmp/stale"], forKey: key)

        let appDelegate = AppDelegate()
        appDelegate.persistOpenFolderURLs()

        XCTAssertEqual(
            UserDefaults.standard.stringArray(forKey: key),
            [],
            "The snapshot kept a folder that has no open window"
        )
    }
}

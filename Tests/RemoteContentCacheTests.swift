import XCTest
@testable import RedmarginCore

final class RemoteContentCacheTests: XCTestCase {
    var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoteContentCacheTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    func testCacheRoundTrip() async {
        let cache = RemoteContentCache(baseDirectory: tempDir)
        let location = RemoteLocation(host: "devtest", path: "/tmp/round-trip.md")

        await cache.save("# Hello\n", for: location)

        let loaded = await cache.load(for: location)
        XCTAssertEqual(loaded, "# Hello\n")
    }

    func testCacheMissReturnsNil() async {
        let cache = RemoteContentCache(baseDirectory: tempDir)
        let loaded = await cache.load(for: RemoteLocation(host: "h", path: "/never-cached.md"))
        XCTAssertNil(loaded)
    }

    func testCacheSkipsOversizedContent() async {
        let cache = RemoteContentCache(baseDirectory: tempDir, maxContentBytes: 16)
        let location = RemoteLocation(host: "h", path: "/big.md")

        await cache.save(String(repeating: "x", count: 100), for: location)

        let loaded = await cache.load(for: location)
        XCTAssertNil(loaded, "Content above the cap should not be written")
    }

    func testCacheEvictsLeastRecentlyWritten() async throws {
        let cache = RemoteContentCache(baseDirectory: tempDir, maxEntries: 2)
        let first = RemoteLocation(host: "h", path: "/first.md")
        let second = RemoteLocation(host: "h", path: "/second.md")
        let third = RemoteLocation(host: "h", path: "/third.md")

        await cache.save("FIRST", for: first)
        try await Task.sleep(nanoseconds: 25_000_000)
        await cache.save("SECOND", for: second)
        try await Task.sleep(nanoseconds: 25_000_000)
        await cache.save("THIRD", for: third)  // exceeds cap of 2 → evict oldest (first)

        let loadedFirst = await cache.load(for: first)
        let loadedThird = await cache.load(for: third)
        XCTAssertNil(loadedFirst, "Oldest-written entry should be evicted")
        XCTAssertEqual(loadedThird, "THIRD", "Newest entry should be kept")
    }

    func testEvictRemovesEntry() async {
        let cache = RemoteContentCache(baseDirectory: tempDir)
        let location = RemoteLocation(host: "h", path: "/evict.md")

        await cache.save("E", for: location)
        await cache.evict(for: location)

        let loaded = await cache.load(for: location)
        XCTAssertNil(loaded)
    }
}

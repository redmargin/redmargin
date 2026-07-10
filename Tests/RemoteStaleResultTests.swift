import XCTest
@testable import Redmargin
@testable import RedmarginCore

/// The remote counterparts of the local last-response-wins races, driven over
/// `FakeRemoteHost` so the response ordering is chosen rather than raced for.
@MainActor
final class RemoteStaleResultTests: XCTestCase {
    private let host = "harness.invalid"
    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoteStaleResultTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    private func makeCache() -> RemoteContentCache {
        RemoteContentCache(baseDirectory: tempDir.appendingPathComponent(UUID().uuidString))
    }

    private func makeState(
        remote: FakeRemoteHost,
        path: String,
        content: String,
        cache: RemoteContentCache
    ) -> RemoteDocumentState {
        RemoteDocumentState(
            content: content,
            location: RemoteLocation(host: host, path: path),
            fileProvider: RemoteFileProvider(connection: remote.connection),
            connectsOnDemand: true,
            contentCache: cache
        )
    }

    /// Clicking a second file in the remote sidebar while the first is still
    /// loading must leave the second on screen.
    func testSlowRemoteSelectionDoesNotReplaceNewerDocument() async throws {
        let remote = await FakeRemoteHost()
        defer { remote.stop() }

        remote.setFile("/remote/start.md", contents: "# Start\n")
        remote.setFile("/remote/slow.md", contents: "# Slow\n", readDelay: 1.5)
        remote.setFile("/remote/fast.md", contents: "# Fast\n")

        let state = makeState(remote: remote, path: "/remote/start.md", content: "# Start\n", cache: makeCache())

        let slowSelection = Task { try await state.loadFile(at: "/remote/slow.md") }
        try await Task.sleep(nanoseconds: 300_000_000)
        try await state.loadFile(at: "/remote/fast.md")

        XCTAssertEqual(state.location.path, "/remote/fast.md")
        XCTAssertEqual(state.content, "# Fast\n")

        _ = await slowSelection.result
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(state.location.path, "/remote/fast.md", "A superseded selection replaced the newer location")
        XCTAssertEqual(state.content, "# Fast\n", "A superseded selection replaced the newer content")
        XCTAssertEqual(state.lastKnownServerContent, "# Fast\n", "A superseded selection replaced the baseline")
        XCTAssertFalse(state.isRefreshing, "A superseded selection left the spinner running")
    }

    /// A remote toggle belongs to the document it was clicked in. Its write, and
    /// everything the write's completion updates (baseline, cache, pending state),
    /// must not be applied to whatever document navigation moved on to.
    func testRemoteCheckboxToggleIsBoundToItsOriginDocument() async throws {
        let remote = await FakeRemoteHost()
        defer { remote.stop() }

        let toggled = "/remote/toggled.md"
        let navigatedTo = "/remote/other.md"
        // The write's reply lands after the navigation completes.
        remote.setFile(toggled, contents: "- [ ] alpha\n", writeDelay: 0.8)
        remote.setFile(navigatedTo, contents: "beta\n")

        let cache = makeCache()
        let state = makeState(remote: remote, path: toggled, content: "- [ ] alpha\n", cache: cache)

        state.handleCheckboxToggle(line: 1, checked: true)
        try await Task.sleep(nanoseconds: 100_000_000)

        // Navigate away while the toggle's write is still in flight.
        try await state.loadFile(at: navigatedTo)
        XCTAssertEqual(state.location.path, navigatedTo)

        // Let the toggle's write reply land on a document it no longer owns.
        try await Task.sleep(nanoseconds: 1_500_000_000)

        XCTAssertEqual(state.content, "beta\n", "The toggle's content overwrote the newly selected document")
        XCTAssertEqual(
            state.lastKnownServerContent,
            "beta\n",
            "The toggle's write applied its baseline to the newly selected document"
        )
        XCTAssertEqual(remote.contents(of: navigatedTo), "beta\n", "The toggle wrote into the newly selected file")
        XCTAssertEqual(remote.contents(of: toggled), "- [x] alpha\n", "The toggle did not reach its own file")

        let writtenPaths = remote.recordedWrites.map(\.path)
        XCTAssertEqual(writtenPaths, [toggled], "The toggle issued a write against the wrong document")

        // The cache must record the toggle under its own location, never under the
        // document the user navigated to.
        let cachedForNavigatedTo = await cache.load(for: RemoteLocation(host: host, path: navigatedTo))
        XCTAssertNotEqual(
            cachedForNavigatedTo,
            "- [x] alpha\n",
            "The toggle cached its content under the newly selected document"
        )
    }
}

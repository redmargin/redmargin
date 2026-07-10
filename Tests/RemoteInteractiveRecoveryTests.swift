import XCTest
@testable import Redmargin
@testable import RedmarginCore

/// The interactive recovery branch of `recoverRemoteOperation`.
///
/// Off the interactive path, last-resort recovery redeploys the server, which is
/// correct but takes tens of seconds. A user gesture (refresh, opening a file from
/// the sidebar) must not freeze the window for that long: it initiates the
/// background reconnect, which self-heals including a redeploy, and fails fast so
/// the window can say "reconnecting" and clear its spinner.
@MainActor
final class RemoteInteractiveRecoveryTests: XCTestCase {
    private let host = "harness.invalid"
    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoteInteractiveRecoveryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    /// A wedged helper: the transport is up, but nothing is ever answered.
    private func makeWedgedHost() async -> FakeRemoteHost {
        let remote = await FakeRemoteHost()
        remote.goSilent()
        return remote
    }

    /// `pingTimeout` is fixed inside the operation support, so the bound below is
    /// the ping plus the reconnect wait this test supplies, plus slack.
    private var boundedInterval: TimeInterval {
        RemoteOperationSupport.pingTimeout + 1 + 6
    }

    /// The defining contract: an interactive operation against a wedged helper
    /// fails with the interactive timeout, which only the interactive branch throws.
    /// Reaching the non-interactive branch would instead redeploy the server inline.
    func testInteractiveOperationFailsWithTheInteractiveTimeout() async throws {
        let remote = await makeWedgedHost()
        defer { remote.stop() }
        let provider = RemoteFileProvider(connection: remote.connection)

        let started = Date()
        do {
            _ = try await readRemoteDocumentContent(
                fileProvider: provider,
                path: "/remote/wedged.md",
                pingFirst: true,
                interactive: true,
                probeTimeout: 1,
                fullTimeout: 2,
                reconnectWaitTimeout: 1
            )
            XCTFail("A wedged helper should not have returned content")
        } catch let error as SSHConnectionError {
            guard case .operationTimeout(let operation) = error else {
                return XCTFail("Expected operationTimeout, got \(error)")
            }
            XCTAssertEqual(
                operation,
                "interactive remote operation",
                "The non-interactive branch ran, which redeploys the server inline"
            )
        }

        let elapsed = Date().timeIntervalSince(started)
        XCTAssertLessThan(elapsed, boundedInterval, "The interactive path did not fail within its bounded interval")
    }

    /// It must initiate a reconnect on the way out; the background loop is what
    /// actually heals the connection (redeploy included).
    func testInteractiveRecoveryInitiatesAReconnect() async throws {
        let remote = await makeWedgedHost()
        defer { remote.stop() }
        let provider = RemoteFileProvider(connection: remote.connection)

        let stateBefore = await remote.connection.getState()
        XCTAssertEqual(stateBefore, .connected)

        _ = try? await readRemoteDocumentContent(
            fileProvider: provider,
            path: "/remote/wedged.md",
            pingFirst: true,
            interactive: true,
            probeTimeout: 1,
            fullTimeout: 2,
            reconnectWaitTimeout: 1
        )

        let stateAfter = await remote.connection.getState()
        XCTAssertNotEqual(stateAfter, .connected, "The interactive path left the connection untouched")
    }

    /// It must not retry the operation after recovery. The non-interactive branch
    /// re-runs it once the server has been redeployed; the interactive branch gives
    /// up so the user can retry.
    func testInteractiveRecoveryDoesNotRetryTheOperation() async throws {
        let remote = await makeWedgedHost()
        defer { remote.stop() }
        let provider = RemoteFileProvider(connection: remote.connection)

        _ = try? await readRemoteDocumentContent(
            fileProvider: provider,
            path: "/remote/wedged.md",
            pingFirst: true,
            interactive: true,
            probeTimeout: 1,
            fullTimeout: 2,
            reconnectWaitTimeout: 1
        )

        let readAttempts = remote.recordedRequests.filter { $0 == RPCMessageType.readFile.rawValue }.count
        XCTAssertLessThanOrEqual(readAttempts, 1, "The operation was retried after recovery")
    }

    /// And the window it was driving must not be left spinning.
    func testInteractiveRefreshClearsTheSpinnerWhenItFails() async throws {
        let remote = await makeWedgedHost()
        defer { remote.stop() }

        let cache = RemoteContentCache(baseDirectory: tempDir.appendingPathComponent(UUID().uuidString))
        let state = RemoteDocumentState(
            content: "# Cached\n",
            location: RemoteLocation(host: host, path: "/remote/wedged.md"),
            fileProvider: RemoteFileProvider(connection: remote.connection),
            connectsOnDemand: true,
            contentCache: cache
        )

        state.refresh()
        XCTAssertTrue(state.isRefreshing, "refresh() should show the spinner immediately")

        let deadline = Date().addingTimeInterval(boundedInterval + 2)
        while state.isRefreshing && Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        XCTAssertFalse(state.isRefreshing, "A failed interactive refresh left the spinner running")
        XCTAssertEqual(state.content, "# Cached\n", "A failed refresh replaced the document")
    }

    /// A failed interactive load must clear its spinner too, and leave the document
    /// it was showing in place.
    func testInteractiveLoadFileClearsTheSpinnerWhenItFails() async throws {
        let remote = await makeWedgedHost()
        defer { remote.stop() }

        let cache = RemoteContentCache(baseDirectory: tempDir.appendingPathComponent(UUID().uuidString))
        let original = RemoteLocation(host: host, path: "/remote/original.md")
        let state = RemoteDocumentState(
            content: "# Original\n",
            location: original,
            fileProvider: RemoteFileProvider(connection: remote.connection),
            connectsOnDemand: true,
            contentCache: cache
        )

        do {
            try await state.loadFile(at: "/remote/wedged.md")
            XCTFail("Loading from a wedged helper should not have succeeded")
        } catch {
            // Expected.
        }

        XCTAssertFalse(state.isRefreshing, "A failed interactive load left the spinner running")
        XCTAssertEqual(state.location, original, "A failed load moved the window off its document")
        XCTAssertEqual(state.content, "# Original\n")
    }
}

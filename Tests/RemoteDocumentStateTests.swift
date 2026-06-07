import XCTest
import Foundation
@testable import Redmargin
@testable import RedmarginCore

@MainActor
final class RemoteDocumentStateTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoteDocumentStateTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    private func makeCache() -> RemoteContentCache {
        RemoteContentCache(baseDirectory: tempDir.appendingPathComponent(UUID().uuidString))
    }

    /// T39: an on-demand window does no network work until `connectIfNeeded`.
    func testOnDemandWindowDoesNoNetworkUntilConnect() async throws {
        let host = "redmargin-\(UUID().uuidString).invalid"
        let location = RemoteLocation(host: host, path: "/tmp/on-demand.md")
        let connection = await SSHConnectionManager.shared.preregisterConnection(for: host)
        let provider = RemoteFileProvider(connection: connection)

        let state = RemoteDocumentState(
            content: "# Cached\n",
            location: location,
            fileProvider: provider,
            connectsOnDemand: true,
            contentCache: makeCache()
        )

        XCTAssertEqual(state.content, "# Cached\n", "Shows cached content immediately")
        XCTAssertEqual(state.connectionPhase, .onDemand, "Starts in the on-demand phase")

        // Give any (incorrectly scheduled) init work a chance to run, then confirm
        // the connection was never opened.
        try await Task.sleep(nanoseconds: 200_000_000)
        let alive = await connection.isAlive()
        XCTAssertFalse(alive, "No connection is opened before connectIfNeeded")
        XCTAssertEqual(state.connectionPhase, .onDemand)

        await SSHConnectionManager.shared.disconnect(host: host)
    }

    /// T41: a hard-unreachable connect error is terminal and maps to the no-route reason.
    func testHostUnreachableMapsToNoRouteReason() {
        XCTAssertEqual(RemoteUnavailableReason.forConnectError(.hostUnreachable(host: "h")), .noRoute)
        XCTAssertEqual(RemoteUnavailableReason.forConnectError(.connectionRefused(host: "h")), .refused)
        XCTAssertEqual(RemoteUnavailableReason.forConnectError(.authenticationFailed(host: "h")), .authFailed)
        XCTAssertEqual(RemoteUnavailableReason.forConnectError(.handshakeTimeout(host: "h")), .serverError)
        XCTAssertEqual(RemoteUnavailableReason.forConnectError(.unexpectedDisconnect), .serverError)
    }

    /// T43: a connect request for this window's location triggers a connect; one for
    /// another location does not.
    func testConnectRequestNotificationTriggersConnect() async throws {
        let host = "redmargin-\(UUID().uuidString).invalid"
        let location = RemoteLocation(host: host, path: "/tmp/me.md")
        let other = RemoteLocation(host: host, path: "/tmp/other.md")
        let connection = await SSHConnectionManager.shared.preregisterConnection(for: host)
        let provider = RemoteFileProvider(connection: connection)

        let state = RemoteDocumentState(
            content: "# Cached\n",
            location: location,
            fileProvider: provider,
            connectsOnDemand: true,
            contentCache: makeCache()
        )
        XCTAssertEqual(state.connectionPhase, .onDemand)

        // A request for a different location must not connect this window.
        NotificationCenter.default.post(name: .remoteWindowConnectRequest, object: other.storageKey)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(state.connectionPhase, .onDemand, "Unrelated location must not trigger a connect")

        // A request for this location drives connectIfNeeded (the .invalid host then
        // fails fast, so the phase leaves .onDemand promptly).
        NotificationCenter.default.post(name: .remoteWindowConnectRequest, object: location.storageKey)
        var moved = false
        for _ in 0..<50 {
            if state.connectionPhase != .onDemand { moved = true; break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(moved, "Connect request for this location triggers connectIfNeeded")

        await SSHConnectionManager.shared.disconnect(host: host)
    }
}

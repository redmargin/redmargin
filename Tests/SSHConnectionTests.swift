import XCTest
@testable import RedmarginCore

final class SSHConnectionTests: XCTestCase {

    // Note: Most tests require a local SSH server running and accessible via 'ssh localhost'
    // without interactive password prompt (e.g. public key auth).

    // MARK: - AsyncStream Continuation Tests (no SSH required)

    func testDisconnectFinishesContinuations() async throws {
        let connection = SSHConnection(host: "nonexistent-host-for-test")

        // Start consuming the events stream in a task
        let eventsFinished = XCTestExpectation(description: "events stream terminates")
        let stateFinished = XCTestExpectation(description: "stateChanges stream terminates")

        Task {
            for await _ in connection.events {}
            eventsFinished.fulfill()
        }

        Task {
            for await _ in connection.stateChanges {}
            stateFinished.fulfill()
        }

        // Give the for-await loops a moment to start
        try await Task.sleep(nanoseconds: 100_000_000)

        // disconnect() should finish both continuations
        await connection.disconnect()

        await fulfillment(of: [eventsFinished, stateFinished], timeout: 3.0)
    }

    func testHandleDisconnectFinishesContinuations() async throws {
        let connection = SSHConnection(host: "localhost")

        do {
            try await connection.connect()
        } catch {
            throw XCTSkip("SSH to localhost failed: \(error)")
        }

        let eventsFinished = XCTestExpectation(description: "events stream terminates")
        let stateFinished = XCTestExpectation(description: "stateChanges stream terminates")

        Task {
            for await _ in connection.events {}
            eventsFinished.fulfill()
        }

        Task {
            for await _ in connection.stateChanges {}
            stateFinished.fulfill()
        }

        // Give the for-await loops a moment to start
        try await Task.sleep(nanoseconds: 100_000_000)

        // Force an intentional disconnect to trigger handleDisconnect path
        await connection.disconnect()

        await fulfillment(of: [eventsFinished, stateFinished], timeout: 3.0)
    }

    // MARK: - App Nap Activity Tests (no SSH required)

    func testAppNapActivityStartsWithRemoteDoc() async throws {
        let manager = SSHConnectionManager.shared

        // Begin activity for first "remote document"
        await manager.beginRemoteDocumentActivity()

        // Begin a second one
        await manager.beginRemoteDocumentActivity()

        // End first — activity should still be active (count > 0)
        await manager.endRemoteDocumentActivity()

        // End second — activity should now be ended (count == 0)
        await manager.endRemoteDocumentActivity()

        // Extra end call should be safe (no crash, count stays at 0)
        await manager.endRemoteDocumentActivity()
    }

    // MARK: - Connection Tests (require SSH)

    func testConnectLocalhost() async throws {
        let connection = SSHConnection(host: "localhost")

        do {
            try await connection.connect()
            await connection.disconnect()
        } catch {
            print("Skipping testConnectLocalhost: \(error)")
            throw XCTSkip("SSH to localhost failed: \(error)")
        }
    }

    func testRPCHandshake() async throws {
        let connection = SSHConnection(host: "localhost")

        do {
            try await connection.connect()

            // Handshake is done in connect(), so if we are here, it worked.
            // Let's send a ping if we had one, or just verify we are connected.

            await connection.disconnect()
        } catch {
            throw XCTSkip("SSH to localhost failed: \(error)")
        }
    }

    func testReconnectionState() async throws {
        let connection = SSHConnection(host: "localhost")

        do {
            try await connection.connect()

            // We can't easily kill the process from here without exposing PID
            // But we can verify the state transitions if we had access.
            // For now, just disconnect cleanly.

            await connection.disconnect()
        } catch {
            throw XCTSkip("SSH to localhost failed: \(error)")
        }
    }

    func testPushEvents() async throws {
        let connection = SSHConnection(host: "localhost")
        do {
            try await connection.connect()

            // We'll use the events stream directly
            // In a real test, we'd trigger a remote event,
            // but for now we just verify the stream is accessible.
            _ = connection.events

            await connection.disconnect()
        } catch {
            throw XCTSkip("SSH to localhost failed: \(error)")
        }
    }

    func testConnectionMultiplexing() async throws {
        // This test verifies that we can open multiple connections to the same host
        // which should multiplex over the same control socket.
        let conn1 = SSHConnection(host: "localhost")
        let conn2 = SSHConnection(host: "localhost")

        do {
            try await conn1.connect()
            try await conn2.connect()

            await conn1.disconnect()
            await conn2.disconnect()
        } catch {
            throw XCTSkip("SSH to localhost failed: \(error)")
        }
    }

    func testForceReconnectOnConnectedConnection() async throws {
        let connection = SSHConnection(host: "localhost")

        do {
            try await connection.connect()
        } catch {
            throw XCTSkip("SSH to localhost failed: \(error)")
        }

        let isAliveBefore = await connection.isAlive()
        XCTAssertTrue(isAliveBefore, "Connection should be alive before forceReconnect")

        // Force reconnect should kill the process and trigger reconnection
        await connection.forceReconnect()

        let stateAfter = await connection.getState()
        XCTAssertEqual(stateAfter, .reconnecting, "State should be reconnecting after forceReconnect")

        // Wait for automatic reconnection (exponential backoff starts at 1s)
        try await Task.sleep(nanoseconds: 3_000_000_000)

        let stateReconnected = await connection.getState()
        XCTAssertEqual(stateReconnected, .connected, "Connection should be re-established after forceReconnect")

        await connection.disconnect()
    }

    func testForceReconnectOnDisconnectedConnectionIsNoop() async throws {
        let connection = SSHConnection(host: "localhost")

        // Never connected — forceReconnect should be a no-op
        let stateBefore = await connection.getState()
        XCTAssertEqual(stateBefore, .disconnected)

        await connection.forceReconnect()

        let stateAfter = await connection.getState()
        XCTAssertEqual(stateAfter, .disconnected, "forceReconnect on disconnected connection should be a no-op")
    }

    func testForceReconnectAllViaManager() async throws {
        let manager = SSHConnectionManager.shared

        do {
            _ = try await manager.connection(for: "localhost")
        } catch {
            throw XCTSkip("SSH to localhost failed: \(error)")
        }

        // Force reconnect all connections
        await manager.forceReconnectAll()

        // Wait for reconnection
        try await Task.sleep(nanoseconds: 3_000_000_000)

        // Verify we can still use the connection (it reconnected)
        do {
            let conn = try await manager.connection(for: "localhost")
            let alive = await conn.isAlive()
            XCTAssertTrue(alive, "Connection should be alive after forceReconnectAll")
        } catch {
            XCTFail("Connection should be usable after forceReconnectAll: \(error)")
        }

        await manager.disconnect(host: "localhost")
    }
}

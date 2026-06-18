import XCTest
@testable import RedmarginCore

final class SSHConnectionTests: XCTestCase {
    private static let testHost = "devtest"

    // MARK: - AsyncStream Continuation Tests

    func testDisconnectFinishesContinuations() async throws {
        let connection = SSHConnection(host: "nonexistent-host-for-test")

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

        try await Task.sleep(nanoseconds: 100_000_000)
        await connection.disconnect()

        await fulfillment(of: [eventsFinished, stateFinished], timeout: 3.0)
    }

    func testHandleDisconnectFinishesContinuations() async throws {
        let connection = SSHConnection(host: Self.testHost)
        try await connection.connect()

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

        try await Task.sleep(nanoseconds: 100_000_000)
        await connection.disconnect()

        await fulfillment(of: [eventsFinished, stateFinished], timeout: 3.0)
    }

    // MARK: - App Nap Activity Tests

    func testAppNapActivityStartsWithRemoteDoc() async throws {
        let manager = SSHConnectionManager.shared

        await manager.beginRemoteDocumentActivity()
        await manager.beginRemoteDocumentActivity()
        await manager.endRemoteDocumentActivity()
        await manager.endRemoteDocumentActivity()
        await manager.endRemoteDocumentActivity()
    }

    // MARK: - Connection Tests

    func testConnectDevtest() async throws {
        let connection = SSHConnection(host: Self.testHost)
        addTeardownBlock { await connection.disconnect() }

        try await connection.connect()

        let isAlive = await connection.isAlive()
        XCTAssertTrue(isAlive, "Connection should be alive after connect")
    }

    func testRPCHandshake() async throws {
        let connection = SSHConnection(host: Self.testHost)
        addTeardownBlock { await connection.disconnect() }

        try await connection.connect()

        let state = await connection.getState()
        XCTAssertEqual(state, .connected, "Handshake should leave the connection connected")
    }

    func testReconnectionState() async throws {
        let connection = SSHConnection(host: Self.testHost)
        addTeardownBlock { await connection.disconnect() }

        try await connection.connect()
        await connection.forceReconnect()

        let immediateState = await connection.getState()
        XCTAssertEqual(immediateState, .reconnecting, "forceReconnect should enter reconnecting state")

        try await waitForConnectionState(connection, .connected, timeout: 15.0)
    }

    func testPushEvents() async throws {
        let connection = SSHConnection(host: Self.testHost)
        addTeardownBlock { await connection.disconnect() }

        try await connection.connect()

        let path = "/tmp/redmargin-ssh-push-\(UUID().uuidString).md"
        _ = try await ProcessRunner.run(
            executable: "ssh",
            arguments: [Self.testHost, "printf '# Push\\n' > \(path)"],
            timeout: 15
        )
        addTeardownBlock {
            _ = try? await ProcessRunner.run(
                executable: "ssh",
                arguments: [Self.testHost, "rm -f \(path)"],
                timeout: 15
            )
        }

        let provider = RemoteFileProvider(connection: connection)
        let expectation = XCTestExpectation(description: "remote file change push event")
        let token = await provider.watchFile(at: path) {
            expectation.fulfill()
        }

        try await Task.sleep(nanoseconds: 500_000_000)
        try await provider.writeFile(at: path, content: "# Changed\n")

        await fulfillment(of: [expectation], timeout: 10.0)
        await provider.unwatch(token)
    }

    func testConnectionMultiplexing() async throws {
        let conn1 = SSHConnection(host: Self.testHost)
        let conn2 = SSHConnection(host: Self.testHost)
        addTeardownBlock {
            await conn1.disconnect()
            await conn2.disconnect()
        }

        try await conn1.connect()
        try await conn2.connect()

        let alive1 = await conn1.isAlive()
        let alive2 = await conn2.isAlive()
        XCTAssertTrue(alive1, "First connection should be alive")
        XCTAssertTrue(alive2, "Second connection should be alive")
    }

    func testForceReconnectOnConnectedConnection() async throws {
        let connection = SSHConnection(host: Self.testHost)
        addTeardownBlock { await connection.disconnect() }

        try await connection.connect()

        let isAliveBefore = await connection.isAlive()
        XCTAssertTrue(isAliveBefore, "Connection should be alive before forceReconnect")

        await connection.forceReconnect()

        let stateAfter = await connection.getState()
        XCTAssertEqual(stateAfter, .reconnecting, "State should be reconnecting after forceReconnect")

        try await waitForConnectionState(connection, .connected, timeout: 15.0)
    }

    func testForceReconnectOnDisconnectedConnectionStartsReconnectPath() async throws {
        let connection = SSHConnection(host: Self.testHost)
        addTeardownBlock { await connection.disconnect() }

        let stateBefore = await connection.getState()
        XCTAssertEqual(stateBefore, .disconnected)

        await connection.forceReconnect()

        let stateAfter = await connection.getState()
        XCTAssertEqual(
            stateAfter,
            .reconnecting,
            "forceReconnect on disconnected connection should start reconnect path"
        )
    }

    func testConnectionManagerReturnsExistingReconnectingConnection() async throws {
        let manager = SSHConnectionManager.shared
        await manager.disconnect(host: Self.testHost)
        addTeardownBlock { await manager.disconnect(host: Self.testHost) }

        let original = try await manager.connection(for: Self.testHost)
        await manager.forceReconnectAll()

        let conn = try await manager.connection(for: Self.testHost)
        XCTAssertTrue(conn === original, "Manager should return the existing reconnecting connection")

        let reusable = await conn.isReusable
        XCTAssertTrue(reusable, "Reconnecting connection should be reusable")
    }

    func testConnectionManagerDisconnectsNonReusableConnectionBeforeReplacement() async throws {
        let manager = SSHConnectionManager.shared
        await manager.disconnect(host: Self.testHost)
        addTeardownBlock { await manager.disconnect(host: Self.testHost) }

        let stale = SSHConnection(host: Self.testHost)
        await stale.disconnect()
        await manager.registerConnection(stale, for: Self.testHost)

        let reusableBefore = await stale.isReusable
        XCTAssertFalse(reusableBefore, "Intentionally disconnected connection should not be reusable")

        let fresh = try await manager.connection(for: Self.testHost)
        XCTAssertFalse(fresh === stale, "Manager should replace a non-reusable connection")

        let alive = await fresh.isAlive()
        XCTAssertTrue(alive, "Replacement connection should be alive")
    }

    func testForceReconnectAllViaManager() async throws {
        let manager = SSHConnectionManager.shared
        await manager.disconnect(host: Self.testHost)
        addTeardownBlock { await manager.disconnect(host: Self.testHost) }

        let original = try await manager.connection(for: Self.testHost)
        await manager.forceReconnectAll()

        try await waitForConnectionState(original, .connected, timeout: 15.0)

        let conn = try await manager.connection(for: Self.testHost)
        XCTAssertTrue(conn === original, "Manager should keep the reconnecting connection instance")

        let alive = await conn.isAlive()
        XCTAssertTrue(alive, "Connection should be alive after forceReconnectAll")
    }

    private func waitForConnectionState(
        _ connection: SSHConnection,
        _ expectedState: SSHConnectionState,
        timeout: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let state = await connection.getState()
            if state == expectedState {
                return
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }

        let finalState = await connection.getState()
        XCTFail("Timed out waiting for \(expectedState); final state was \(finalState)", file: file, line: line)
    }
}

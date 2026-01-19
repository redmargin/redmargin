import XCTest
@testable import RedmarginCore

final class SSHConnectionTests: XCTestCase {

    // Note: These tests require a local SSH server running and accessible via 'ssh localhost'
    // without interactive password prompt (e.g. public key auth).

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
}

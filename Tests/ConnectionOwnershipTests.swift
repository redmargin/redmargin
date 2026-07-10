import XCTest
@testable import RedmarginCore

/// `SSHConnectionManager` is the single owner of a host's connection. Anything
/// that displaces its entry strands the windows already holding the old object:
/// wake-from-sleep reconnect and quit-time shutdown walk the manager's table, so
/// an orphaned connection is never reconnected and never closed.
final class ConnectionOwnershipTests: XCTestCase {
    /// Never connected to; these tests only exercise ownership bookkeeping.
    private func unreachableHost() -> String {
        "redmargin-\(UUID().uuidString).invalid"
    }

    override func tearDown() async throws {
        // The manager is a singleton; leave no entries behind for other suites.
        await SSHConnectionManager.shared.disconnectAll()
    }

    /// The regression: the remote-open sheet built its own connection and then
    /// registered it, silently replacing the entry the open windows were using.
    func testRegisteringASecondConnectionDoesNotDisplaceALiveOne() async throws {
        let host = unreachableHost()
        let manager = SSHConnectionManager.shared

        let original = await manager.preregisterConnection(for: host)
        let interloper = SSHConnection(host: host)

        let adopted = await manager.registerConnection(interloper, for: host)

        XCTAssertFalse(adopted, "A second connection displaced the one windows are using")
        let current = await manager.preregisterConnection(for: host)
        XCTAssertTrue(current === original, "The manager handed out the interloping connection")
    }

    /// A connection that was intentionally disconnected is not usable, so it is
    /// replaced rather than kept.
    func testRegisteringOverANonReusableConnectionSucceeds() async throws {
        let host = unreachableHost()
        let manager = SSHConnectionManager.shared

        let retired = await manager.preregisterConnection(for: host)
        await retired.disconnect()
        let reusable = await retired.isReusable
        XCTAssertFalse(reusable)

        let replacement = SSHConnection(host: host)
        let adopted = await manager.registerConnection(replacement, for: host)

        XCTAssertTrue(adopted, "A retired connection blocked its own replacement")
        let current = await manager.preregisterConnection(for: host)
        XCTAssertTrue(current === replacement)
    }

    /// Re-registering the same object is not a replacement.
    func testRegisteringTheSameConnectionIsIdempotent() async throws {
        let host = unreachableHost()
        let manager = SSHConnectionManager.shared

        let connection = await manager.preregisterConnection(for: host)
        let adopted = await manager.registerConnection(connection, for: host)

        XCTAssertTrue(adopted)
        let current = await manager.preregisterConnection(for: host)
        XCTAssertTrue(current === connection)
    }

    /// Every window on a host shares one connection object, which is what makes
    /// `forceReconnectAll` and `disconnectAll` reach all of them.
    func testAllWindowsOnAHostShareOneConnection() async throws {
        let host = unreachableHost()
        let manager = SSHConnectionManager.shared

        let first = await manager.preregisterConnection(for: host)
        let second = await manager.preregisterConnection(for: host)

        XCTAssertTrue(first === second)
    }
}

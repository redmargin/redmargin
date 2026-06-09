import XCTest
@testable import RedmarginCore

final class SSHConnectionManagerTests: XCTestCase {
    func testPreregisterReturnsSharedConnectionPerHost() async {
        let manager = SSHConnectionManager.shared
        let host = "preregister-\(UUID().uuidString)"

        let first = await manager.preregisterConnection(for: host)
        let second = await manager.preregisterConnection(for: host)
        XCTAssertTrue(first === second, "Same host returns the same connection instance")

        let other = await manager.preregisterConnection(for: "other-\(UUID().uuidString)")
        XCTAssertFalse(first === other, "A different host returns a distinct connection")

        await manager.disconnect(host: host)
    }

    func testEnsureConnectedCoalescesConcurrentCallers() async {
        let manager = SSHConnectionManager.shared
        // TEST-NET-1 address: guaranteed unroutable, so the connect fails fast with no
        // real server. Two concurrent callers must coalesce into one connect attempt.
        let host = "192.0.2.\(Int.random(in: 2...250))"

        let before = await manager.connectStartCount
        async let first: Void = { _ = try? await manager.ensureConnected(for: host) }()
        async let second: Void = { _ = try? await manager.ensureConnected(for: host) }()
        _ = await (first, second)
        let after = await manager.connectStartCount

        XCTAssertEqual(after - before, 1, "Concurrent callers share a single connect attempt")
        await manager.disconnect(host: host)
    }
}

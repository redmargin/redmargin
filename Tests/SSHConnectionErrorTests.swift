import XCTest
@testable import RedmarginCore

final class SSHConnectionErrorTests: XCTestCase {
    func testConnectionTimeoutMessageDoesNotClaimHostIsUnreachable() {
        XCTAssertEqual(
            SSHConnectionError.connectionTimeout(host: "wraith").localizedDescription,
            "SSH connection to wraith timed out before the remote helper started."
        )
    }

    func testHelperStartupTimeoutIncludesRemoteStderr() {
        XCTAssertEqual(
            SSHConnectionError
                .helperStartupTimeout(host: "wraith", stderr: "Failed to spawn daemon")
                .localizedDescription,
            "Redmargin connected to wraith, but the remote helper did not finish starting: Failed to spawn daemon"
        )
    }
}

import XCTest
@testable import RedmarginCore

final class ServerDeployerTests: XCTestCase {
    func testLocalBinaryNameSupportsIntelMacRemotes() {
        XCTAssertEqual(
            ServerDeployer.localBinaryName(osName: "Darwin", arch: "x86_64"),
            "redmargin-server-x86_64-darwin"
        )
    }

    func testLocalBinaryNameSupportsAppleSiliconMacRemotes() {
        XCTAssertEqual(
            ServerDeployer.localBinaryName(osName: "Darwin", arch: "arm64"),
            "redmargin-server-aarch64-darwin"
        )
    }

    func testLocalBinaryNameSupportsLinuxX86Remotes() {
        XCTAssertEqual(
            ServerDeployer.localBinaryName(osName: "Linux", arch: "x86_64"),
            "redmargin-server-x86_64-linux"
        )
    }
}

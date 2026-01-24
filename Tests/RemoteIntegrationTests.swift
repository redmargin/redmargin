import XCTest
@testable import RedmarginCore

final class RemoteIntegrationTests: XCTestCase {

    func testServerDeployer() async throws {
        let deployer = ServerDeployer()
        print("[Test] Testing deployment to devtest...")

        do {
            // First, delete any existing binary to force deployment
            _ = try await ProcessRunner.run(executable: "ssh", arguments: ["devtest", "rm -rf ~/.redmargin-server"])

            let remotePath = try await deployer.ensureServerDeployed(host: "devtest")
            XCTAssertTrue(remotePath.contains("redmargin-server"))
            print("[Test] Server deployed to \(remotePath)")

            // Verify it exists and is executable
            let check = try await ProcessRunner.run(executable: "ssh", arguments: ["devtest", "test -x \(remotePath)"])
            XCTAssertEqual(check.exitCode, 0)
        } catch {
            XCTFail("Deployment failed: \(error)")
        }
    }

    func testRemoteFileProvider() async throws {
        let connection = SSHConnection(host: "devtest")
        try await connection.connect()

        let provider = RemoteFileProvider(connection: connection)
        let tempPath = "/tmp/redmargin-provider-test.md"

        print("[Test] Testing RemoteFileProvider operations...")

        // 1. Write
        let content = "Hello from Provider"
        try await provider.writeFile(at: tempPath, content: content)

        // 2. Read
        let readContent = try await provider.readFile(at: tempPath)
        XCTAssertEqual(readContent, content)

        // 3. Watch
        let expectation = XCTestExpectation(description: "Watch callback")
        let token = await provider.watchFile(at: tempPath) {
            print("[Test] Watch callback triggered!")
            expectation.fulfill()
        }

        // Wait for watcher to register
        try await Task.sleep(nanoseconds: 500_000_000)

        // Trigger change
        try await provider.writeFile(at: tempPath, content: "Changed content")

        await fulfillment(of: [expectation], timeout: 5.0)

        // 4. Unwatch
        await provider.unwatch(token)

        await connection.disconnect()
    }

    func testControlSocketReuse() async throws {
        let conn1 = SSHConnection(host: "devtest")
        let conn2 = SSHConnection(host: "devtest")

        print("[Test] Testing SSH control socket reuse (multiplexing)...")

        try await conn1.connect()
        print("[Test] Connection 1 established (primary)")

        try await conn2.connect()
        print("[Test] Connection 2 established (multiplexed)")

        await conn1.disconnect()
        await conn2.disconnect()
        print("[Test] Connections closed.")
    }

    func testReadAsset() async throws {
        let connection = SSHConnection(host: "devtest")
        try await connection.connect()

        let provider = RemoteFileProvider(connection: connection)

        print("[Test] Testing ReadAsset RPC...")

        // Create a test binary file on the remote server
        let testPath = "/tmp/redmargin-test-asset.png"
        // Create a minimal valid PNG (1x1 transparent pixel)
        let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAA" +
            "DUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        _ = try await ProcessRunner.run(
            executable: "ssh",
            arguments: ["devtest", "echo '\(pngBase64)' | base64 -d > \(testPath)"]
        )

        // Read the asset via our RPC
        let (data, mimeType) = try await provider.readAsset(at: testPath)

        print("[Test] Got asset: \(data.count) bytes, mimeType: \(mimeType)")
        XCTAssertGreaterThan(data.count, 0)
        XCTAssertEqual(mimeType, "image/png")

        // Cleanup
        _ = try await ProcessRunner.run(executable: "ssh", arguments: ["devtest", "rm -f \(testPath)"])

        await connection.disconnect()
        print("[Test] ReadAsset test passed!")
    }
}

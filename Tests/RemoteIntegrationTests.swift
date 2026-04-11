import XCTest
@testable import Redmargin
@testable import RedmarginLib
@testable import RedmarginCore

final class RemoteIntegrationTests: XCTestCase {

    func testSlowRemoteReadRecoversAfterProbeTimeout() async throws {
        let connection = SSHConnection(host: "devtest")
        try await connection.connect()

        let provider = RemoteFileProvider(connection: connection)
        let fifoPath = "/tmp/redmargin-slow-read.fifo"

        defer {
            Task {
                _ = try? await ProcessRunner.run(
                    executable: "ssh",
                    arguments: ["devtest", "rm -f \(fifoPath)"],
                    timeout: 15
                )
                await connection.disconnect()
            }
        }

        try await prepareSlowRemoteFIFO(
            path: fifoPath,
            writes: [
                (delay: 6, content: "# Slow\n"),
                (delay: 12, content: "# Slow\n")
            ]
        )

        let content = try await readRemoteDocumentContent(
            fileProvider: provider,
            path: fifoPath,
            pingFirst: false,
            probeTimeout: 5,
            fullTimeout: 20,
            reconnectWaitTimeout: 15
        )

        XCTAssertEqual(content, "# Slow\n")
    }

    @MainActor
    func testLoadFileDoesNotApplyCancelledRefreshResult() async throws {
        let connection = SSHConnection(host: "devtest")
        try await connection.connect()

        let provider = RemoteFileProvider(connection: connection)
        let slowPath = "/tmp/redmargin-refresh-race.fifo"
        let fastPath = "/tmp/redmargin-refresh-race-fast.md"

        defer {
            Task {
                _ = try? await ProcessRunner.run(
                    executable: "ssh",
                    arguments: ["devtest", "rm -f \(slowPath) \(fastPath)"],
                    timeout: 15
                )
                await connection.disconnect()
            }
        }

        try await prepareSlowRemoteFIFO(
            path: slowPath,
            writes: [
                (delay: 6, content: "# Slow\n"),
                (delay: 12, content: "# Slow\n")
            ]
        )
        _ = try await ProcessRunner.run(
            executable: "ssh",
            arguments: ["devtest", "printf '# Fast\\n' > \(fastPath)"],
            timeout: 15
        )

        let state = RemoteDocumentState(
            content: "# Initial\n",
            location: RemoteLocation(host: "devtest", path: slowPath),
            fileProvider: provider
        )

        state.refresh()
        try await Task.sleep(nanoseconds: 250_000_000)
        try await state.loadFile(at: fastPath)

        XCTAssertEqual(state.location.path, fastPath)
        XCTAssertEqual(state.content, "# Fast\n")

        try await Task.sleep(nanoseconds: 8_000_000_000)

        XCTAssertEqual(state.location.path, fastPath)
        XCTAssertEqual(state.content, "# Fast\n")
    }

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

    func testRemoteDirectoryWatchRecoversAfterReconnect() async throws {
        let connection = SSHConnection(host: "devtest")
        try await connection.connect()

        let provider = RemoteFileProvider(connection: connection)
        let testDir = "/tmp/redmargin-watch-recovery-test"

        // Setup: create test directory with a file
        _ = try await ProcessRunner.run(
            executable: "ssh",
            arguments: ["devtest", "rm -rf \(testDir) && mkdir -p \(testDir) && echo '# Test' > \(testDir)/before.md"]
        )

        // Create tree provider watching the directory
        let treeProvider = await RemoteFileTreeProvider(
            currentFilePath: testDir,
            fileProvider: provider,
            reconnectHost: "devtest",
            isDirectory: true,
            expandedFoldersLoader: { _ in Set<String>() }
        )

        // Wait for initial load
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let isLoading = await treeProvider.isLoading
            let rootNodes = await treeProvider.rootNodes
            if !isLoading && !rootNodes.isEmpty { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        let rootNodes = await treeProvider.rootNodes
        XCTAssertFalse(rootNodes.isEmpty, "Should have loaded initial directory listing")

        // Force reconnect
        await connection.forceReconnect()

        // Wait for reconnection (up to 15s)
        let reconnectDeadline = Date().addingTimeInterval(15)
        while Date() < reconnectDeadline {
            let state = await connection.getState()
            if state == .connected { break }
            try await Task.sleep(nanoseconds: 500_000_000)
        }

        // Add a file after reconnect
        _ = try await ProcessRunner.run(
            executable: "ssh",
            arguments: ["devtest", "echo '# After' > \(testDir)/after.md"]
        )

        // Wait for the watch to detect the new file
        let watchDeadline = Date().addingTimeInterval(10)
        var foundAfter = false
        while Date() < watchDeadline {
            let nodes = await treeProvider.rootNodes
            if nodes.contains(where: { $0.name == "after.md" }) {
                foundAfter = true
                break
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }

        XCTAssertTrue(foundAfter, "Watch should recover after reconnect and detect new files")

        // Cleanup
        _ = try await ProcessRunner.run(
            executable: "ssh",
            arguments: ["devtest", "rm -rf \(testDir)"]
        )
        await connection.disconnect()
    }

    func testRemoteFolderSidebarRefreshDoesNotForceDocumentReconnect() async throws {
        let connection = SSHConnection(host: "devtest")
        try await connection.connect()

        let provider = RemoteFileProvider(connection: connection)
        let testDir = "/tmp/redmargin-folder-refresh-test"

        // Setup: create test directory
        _ = try await ProcessRunner.run(
            executable: "ssh",
            arguments: ["devtest", "rm -rf \(testDir) && mkdir -p \(testDir) && echo '# Test' > \(testDir)/file.md"]
        )

        // Create tree provider in folder mode (no file selected)
        let treeProvider = await RemoteFileTreeProvider(
            currentFilePath: testDir,
            fileProvider: provider,
            reconnectHost: "devtest",
            isDirectory: true,
            expandedFoldersLoader: { _ in Set<String>() }
        )

        // Wait for initial load
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let isLoading = await treeProvider.isLoading
            let rootNodes = await treeProvider.rootNodes
            if !isLoading && !rootNodes.isEmpty { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        // Trigger sidebar-only refresh (folder mode)
        await treeProvider.refresh()

        // Wait for refresh to complete
        let refreshDeadline = Date().addingTimeInterval(5)
        while Date() < refreshDeadline {
            let isLoading = await treeProvider.isLoading
            if !isLoading { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        // Connection should still be alive — sidebar refresh didn't force a document read
        let alive = await connection.isAlive()
        XCTAssertTrue(alive, "Connection should remain alive after folder-only sidebar refresh")

        // Cleanup
        _ = try await ProcessRunner.run(
            executable: "ssh",
            arguments: ["devtest", "rm -rf \(testDir)"]
        )
        await connection.disconnect()
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

    private func prepareSlowRemoteFIFO(
        path: String,
        writes: [(delay: Int, content: String)]
    ) async throws {
        let writerCommands = writes.map { write in
            let content = write.content
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "'\\''")
            return "(sleep \(write.delay); printf '\(content)' > \(path)) &"
        }.joined(separator: " ")

        _ = try await ProcessRunner.run(
            executable: "ssh",
            arguments: ["devtest", "rm -f \(path) && mkfifo \(path) && \(writerCommands)"],
            timeout: 15
        )
    }
}

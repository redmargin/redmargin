import XCTest
@testable import Redmargin
@testable import RedmarginLib
@testable import RedmarginCore

final class RemoteIntegrationTests: WindowlessTestCase {
    private var backgroundProcesses: [Process] = []
    private var savedRecentWorkspacesData: Data?

    override func setUp() {
        super.setUp()
        savedRecentWorkspacesData = UserDefaults.standard.data(forKey: RecentWorkspaceStore.defaultsKey)
        UserDefaults.standard.removeObject(forKey: RecentWorkspaceStore.defaultsKey)
    }

    func testRemoteReadReturnsRegularFileContent() async throws {
        let connection = SSHConnection(host: "devtest")
        try await connection.connect()

        let provider = RemoteFileProvider(connection: connection)
        let path = "/tmp/redmargin-remote-read.md"

        defer {
            Task {
                _ = try? await ProcessRunner.run(
                    executable: "ssh",
                    arguments: ["devtest", "rm -f \(path)"],
                    timeout: 15
                )
                await connection.disconnect()
            }
        }

        _ = try await ProcessRunner.run(
            executable: "ssh",
            arguments: ["devtest", "printf '# Slow\\n' > \(path)"],
            timeout: 15
        )

        let content = try await readRemoteDocumentContent(
            fileProvider: provider,
            path: path,
            pingFirst: false,
            probeTimeout: 5,
            fullTimeout: 20,
            reconnectWaitTimeout: 15
        )

        XCTAssertEqual(content, "# Slow\n")
    }

    @MainActor
    func testOpeningRemoteFileRecordsRecentWorkspace() {
        let appDelegate = AppDelegate()
        let path = "/tmp/redmargin-recent-remote-file-\(UUID().uuidString).md"
        let location = RemoteLocation(host: "devtest", path: path)

        appDelegate.recordRemoteDocumentRecent(host: "devtest", path: path)

        let item = appDelegate.recentWorkspaces.items.first { item in
            item.kind == .remoteFile && item.remoteLocation == location
        }
        XCTAssertNotNil(item)
    }

    @MainActor
    func testOpeningRemoteFolderRecordsRecentWorkspace() {
        let appDelegate = AppDelegate()
        let path = "/tmp/redmargin-recent-remote-folder-\(UUID().uuidString)"
        let folderPath = path + "/"
        let location = RemoteLocation(host: "devtest", path: folderPath)

        appDelegate.recordRemoteFolderRecent(host: "devtest", path: path)

        let item = appDelegate.recentWorkspaces.items.first { item in
            item.kind == .remoteFolder && item.remoteLocation == location
        }
        XCTAssertNotNil(item)
    }

    @MainActor
    func testFailedRemoteRecentOpenKeepsEntry() async throws {
        let appDelegate = AppDelegate()
        let location = RemoteLocation(host: "devtest", path: "/tmp/redmargin-missing-\(UUID().uuidString)/")
        let item = RecentWorkspaceItem.remoteFolder(location)
        appDelegate.recentWorkspaces.add(item)

        let succeeded = await appDelegate.retryRecentWorkspace(item)

        XCTAssertFalse(succeeded)
        let storedItem = appDelegate.recentWorkspaces.items.first { $0.storageKey == item.storageKey }
        XCTAssertNotNil(storedItem)
        XCTAssertFalse(storedItem?.lastFailureReason?.isEmpty ?? true)
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

    /// Kills the remote helpers, in its own command.
    ///
    /// `pkill -f` matches whole command lines, so it matches the remote shell
    /// running it if that command line mentions the pattern anywhere. Bracketing
    /// hides the pattern in the pkill itself, but any *other* word on the same line
    /// (`rm -rf ~/.redmargin-server`, `mkdir -p ~/.redmargin-server`) still matches
    /// and the shell kills itself before reaching it. Hence: pkill alone.
    private func stopRemoteHelpers() async throws {
        _ = try await devtestShell("pkill -f '[r]edmargin-server' 2>/dev/null || true")
    }

    /// Runs `command` on devtest and returns its trimmed stdout.
    private func devtestShell(_ command: String) async throws -> (stdout: String, exitCode: Int32) {
        let result = try await ProcessRunner.run(
            executable: "ssh",
            arguments: ["-o", "BatchMode=yes", "devtest", command],
            timeout: 20
        )
        return (result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), result.exitCode)
    }

    /// A deploy that fails at the install step must leave the previously working
    /// binary exactly where it was. The upload lands on a temp path, so nothing is
    /// overwritten until the rename succeeds.
    func testFailedInstallLeavesTheExistingBinaryIntact() async throws {
        let version = AppVersion.current
        let binaryPath = "~/.redmargin-server/redmargin-server-\(version)"
        let tempPath = "~/.redmargin-server/.redmargin-server-\(version).tmp"
        let deployer = ServerDeployer()

        try await stopRemoteHelpers()
        _ = try await devtestShell("mkdir -p ~/.redmargin-server")
        // A sentinel standing in for a good, already-installed binary. Left
        // non-executable so the deploy does not short-circuit on the `test -x` check.
        _ = try await devtestShell("printf 'SENTINEL' > \(binaryPath) && chmod 644 \(binaryPath)")
        // Make the rename fail: mv refuses to overwrite a file with a directory.
        _ = try await devtestShell("rm -rf \(tempPath) && mkdir -p \(tempPath)")

        defer {
            Task {
                _ = try? await self.devtestShell("rm -rf \(tempPath) \(binaryPath)")
            }
        }

        do {
            _ = try await deployer.ensureServerDeployed(host: "devtest")
            XCTFail("Deploy should have failed at the install step")
        } catch let error as ServerDeployerError {
            guard case .uploadFailed = error else {
                return XCTFail("Expected uploadFailed, got \(error)")
            }
        }

        // The upload itself succeeded (scp wrote into the temp directory), so the
        // deploy really did fail at the rename rather than earlier.
        let uploaded = try await devtestShell("test -f \(tempPath)/redmargin-server-x86_64-linux")
        XCTAssertEqual(uploaded.exitCode, 0, "The upload did not complete; this test never reached the install step")

        let sentinel = try await devtestShell("cat \(binaryPath)")
        XCTAssertEqual(sentinel.stdout, "SENTINEL", "A failed install replaced the working binary")
    }

    /// Cleanup after a deploy removes other versions' binaries and nothing else:
    /// the running daemon's socket and pid file have to survive it.
    func testCleanupRemovesOnlyOtherVersionBinaries() async throws {
        let version = AppVersion.current
        let deployer = ServerDeployer()

        try await stopRemoteHelpers()
        _ = try await devtestShell("rm -rf ~/.redmargin-server")
        _ = try await devtestShell(
            """
            mkdir -p ~/.redmargin-server && \
            printf 'old' > ~/.redmargin-server/redmargin-server-0.0.1 && \
            printf 'old' > ~/.redmargin-server/redmargin-server-0.0.2 && \
            printf 'pid' > ~/.redmargin-server/daemon.pid && \
            printf 'log' > ~/.redmargin-server/daemon.stderr.log
            """
        )

        _ = try await deployer.ensureServerDeployed(host: "devtest")

        let survivors = try await devtestShell("ls -A ~/.redmargin-server | sort | tr '\\n' ' '")
        XCTAssertFalse(survivors.stdout.contains("redmargin-server-0.0.1"), "An old version binary survived cleanup")
        XCTAssertFalse(survivors.stdout.contains("redmargin-server-0.0.2"), "An old version binary survived cleanup")
        XCTAssertTrue(survivors.stdout.contains("redmargin-server-\(version)"), "The deployed binary was deleted")
        XCTAssertTrue(survivors.stdout.contains("daemon.pid"), "Cleanup deleted the daemon pid file")
        XCTAssertTrue(survivors.stdout.contains("daemon.stderr.log"), "Cleanup deleted the daemon log")

        // And the deploy left no partial upload behind.
        let leftoverTemp = try await devtestShell("test -e ~/.redmargin-server/.redmargin-server-\(version).tmp")
        XCTAssertNotEqual(leftoverTemp.exitCode, 0, "A temp upload was left behind")

        let installed = try await devtestShell("test -x ~/.redmargin-server/redmargin-server-\(version)")
        XCTAssertEqual(installed.exitCode, 0, "The installed binary is not executable")
    }

    /// `removeDeployedServer` is what the version-skew self-heal and the forced
    /// restart rely on: if it does not actually delete the binary, the next deploy
    /// sees a matching hash, short-circuits, and the stale daemon survives.
    func testRemoveDeployedServerActuallyRemovesTheBinary() async throws {
        let version = AppVersion.current
        let binaryPath = "~/.redmargin-server/redmargin-server-\(version)"
        let deployer = ServerDeployer()

        _ = try await deployer.ensureServerDeployed(host: "devtest")
        let installed = try await devtestShell("test -x \(binaryPath)")
        XCTAssertEqual(installed.exitCode, 0, "Setup failed: the binary was not deployed")

        await deployer.removeDeployedServer(host: "devtest")

        let stillThere = try await devtestShell("test -e \(binaryPath)")
        XCTAssertNotEqual(stillThere.exitCode, 0, "removeDeployedServer left the binary in place")
    }

    func testServerDeployer() async throws {
        let deployer = ServerDeployer()
        print("[Test] Testing deployment to devtest...")

        do {
            // First, delete any existing binary to force deployment
            _ = try await ProcessRunner.run(
                executable: "ssh",
                arguments: ["devtest", "rm -rf ~/.redmargin-server"],
                timeout: 15
            )

            let remotePath = try await deployer.ensureServerDeployed(host: "devtest")
            XCTAssertTrue(remotePath.contains("redmargin-server"))
            print("[Test] Server deployed to \(remotePath)")

            // Verify it exists and is executable
            let check = try await ProcessRunner.run(
                executable: "ssh",
                arguments: ["devtest", "test -x \(remotePath)"],
                timeout: 15
            )
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

        // No wait here: watchFile only returns once the helper has answered the WatchFile
        // request, so the remote watcher is already registered by the time the token is
        // in hand. Sleeping for it hid whether that was true.

        // Trigger change
        try await provider.writeFile(at: tempPath, content: "Changed content")

        await fulfillment(of: [expectation], timeout: 5.0)

        // 4. Unwatch
        await provider.unwatch(token)

        await connection.disconnect()
    }

    /// ControlMaster is deliberately disabled (`SSHConnection.swift:353`), so two
    /// connections to one host are independent ssh sessions rather than a multiplexed
    /// pair. Each must work on its own, and closing one must leave the other usable.
    func testTwoConnectionsToTheSameHostAreIndependent() async throws {
        let conn1 = SSHConnection(host: "devtest")
        let conn2 = SSHConnection(host: "devtest")
        addTeardownBlock {
            await conn1.disconnect()
            await conn2.disconnect()
        }

        try await conn1.connect()
        try await conn2.connect()

        var firstAlive = await conn1.isAlive()
        var secondAlive = await conn2.isAlive()
        XCTAssertTrue(firstAlive, "First connection should be alive")
        XCTAssertTrue(secondAlive, "Second connection to the same host should be alive")

        // Closing one must not take the other down with it.
        await conn1.disconnect()

        firstAlive = await conn1.isAlive()
        secondAlive = await conn2.isAlive()
        XCTAssertFalse(firstAlive, "A disconnected connection must not report alive")
        XCTAssertTrue(secondAlive, "Closing one connection must not close the other")

        // And the survivor still serves requests.
        let provider = RemoteFileProvider(connection: conn2)
        let entries = try await provider.listDirectory(at: "/tmp")
        XCTAssertFalse(entries.isEmpty, "The surviving connection should still answer RPCs")
    }

    func testRemoteDirectoryWatchRecoversAfterReconnect() async throws {
        let connection = SSHConnection(host: "devtest")
        try await connection.connect()

        let provider = RemoteFileProvider(connection: connection)
        let testDir = "/tmp/redmargin-watch-recovery-test"
        defer {
            Task {
                _ = try? await ProcessRunner.run(
                    executable: "ssh",
                    arguments: ["devtest", "rm -rf \(testDir)"],
                    timeout: 15
                )
                await connection.disconnect()
            }
        }

        // Setup: create test directory with a file
        _ = try await ProcessRunner.run(
            executable: "ssh",
            arguments: ["devtest", "rm -rf \(testDir) && mkdir -p \(testDir) && echo '# Test' > \(testDir)/before.md"],
            timeout: 15
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
            arguments: ["devtest", "echo '# After' > \(testDir)/after.md"],
            timeout: 15
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
            arguments: ["devtest", "rm -rf \(testDir) && mkdir -p \(testDir) && echo '# Test' > \(testDir)/file.md"],
            timeout: 15
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
            arguments: ["devtest", "rm -rf \(testDir)"],
            timeout: 15
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
            arguments: ["devtest", "echo '\(pngBase64)' | base64 -d > \(testPath)"],
            timeout: 15
        )

        // Read the asset via our RPC
        let (data, mimeType) = try await provider.readAsset(at: testPath)

        print("[Test] Got asset: \(data.count) bytes, mimeType: \(mimeType)")
        XCTAssertGreaterThan(data.count, 0)
        XCTAssertEqual(mimeType, "image/png")

        // Cleanup
        _ = try await ProcessRunner.run(
            executable: "ssh",
            arguments: ["devtest", "rm -f \(testPath)"],
            timeout: 15
        )

        await connection.disconnect()
        print("[Test] ReadAsset test passed!")
    }

    // MARK: - On-demand restore (remote window restore UX)

    private func makeTempCache() -> (RemoteContentCache, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoteRestoreCache-\(UUID().uuidString)")
        return (RemoteContentCache(baseDirectory: dir), dir)
    }

    @MainActor
    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return condition()
    }

    /// T46/T40: a pre-seeded cache shows immediately before connect; connecting
    /// revalidates against the (changed) server content and refreshes the cache.
    @MainActor
    func testOnDemandWindowShowsCachedContentBeforeConnect() async throws {
        let path = "/tmp/redmargin-ondemand-\(UUID().uuidString).md"
        let location = RemoteLocation(host: "devtest", path: path)
        let (cache, cacheDir) = makeTempCache()
        defer {
            try? FileManager.default.removeItem(at: cacheDir)
            Task {
                _ = try? await ProcessRunner.run(
                    executable: "ssh", arguments: ["devtest", "rm -f \(path)"], timeout: 15
                )
            }
        }

        // Cache holds stale content; the server holds different, live content.
        await cache.save("# Cached\n", for: location)
        _ = try await ProcessRunner.run(
            executable: "ssh", arguments: ["devtest", "printf '# Live\\n' > \(path)"], timeout: 15
        )

        let connection = await SSHConnectionManager.shared.preregisterConnection(for: "devtest")
        let provider = RemoteFileProvider(connection: connection)
        let state = RemoteDocumentState(
            content: cache.loadSync(for: location) ?? "",
            location: location,
            fileProvider: provider,
            connectsOnDemand: true,
            contentCache: cache
        )

        XCTAssertEqual(state.content, "# Cached\n", "Cached content shows immediately")
        XCTAssertEqual(state.connectionPhase, .onDemand)
        let aliveBefore = await connection.isAlive()
        XCTAssertFalse(aliveBefore, "No connection before connectIfNeeded")

        await state.connectIfNeeded()

        XCTAssertEqual(state.connectionPhase, .connected)
        XCTAssertEqual(state.content, "# Live\n", "Revalidated to live server content")
        let cacheRefreshed = await waitUntil(timeout: 5) { cache.loadSync(for: location) == "# Live\n" }
        XCTAssertTrue(cacheRefreshed, "Cache is refreshed with the revalidated content")
    }

    /// T47: the frontmost window connects immediately; the rest warm in the
    /// background and reach connected without an explicit focus.
    @MainActor
    func testFrontmostConnectsAndOthersWarmInBackground() async throws {
        let path1 = "/tmp/redmargin-warm1-\(UUID().uuidString).md"
        let path2 = "/tmp/redmargin-warm2-\(UUID().uuidString).md"
        let loc1 = RemoteLocation(host: "devtest", path: path1)
        let loc2 = RemoteLocation(host: "devtest", path: path2)
        let (cache, cacheDir) = makeTempCache()
        defer {
            try? FileManager.default.removeItem(at: cacheDir)
            Task {
                _ = try? await ProcessRunner.run(
                    executable: "ssh", arguments: ["devtest", "rm -f \(path1) \(path2)"], timeout: 15
                )
            }
        }
        _ = try await ProcessRunner.run(
            executable: "ssh",
            arguments: ["devtest", "printf '# One\\n' > \(path1); printf '# Two\\n' > \(path2)"],
            timeout: 15
        )

        let connection = await SSHConnectionManager.shared.preregisterConnection(for: "devtest")
        let state1 = RemoteDocumentState(
            content: "", location: loc1, fileProvider: RemoteFileProvider(connection: connection),
            connectsOnDemand: true, contentCache: cache
        )
        let state2 = RemoteDocumentState(
            content: "", location: loc2, fileProvider: RemoteFileProvider(connection: connection),
            connectsOnDemand: true, contentCache: cache
        )

        let appDelegate = AppDelegate()
        appDelegate.remoteDocumentWindows[loc1] = NSWindow()
        appDelegate.remoteDocumentWindows[loc2] = NSWindow()

        // Frontmost connects immediately; the rest warm quietly in the background.
        NotificationCenter.default.post(name: .remoteWindowConnectRequest, object: loc1.storageKey)
        appDelegate.startBackgroundRemoteWarm(skipping: loc1)

        let frontUp = await waitUntil(timeout: 30) { state1.connectionPhase == .connected }
        XCTAssertTrue(frontUp, "Frontmost window connects")
        let secondUp = await waitUntil(timeout: 30) { state2.connectionPhase == .connected }
        XCTAssertTrue(secondUp, "Background warm connects the second window without explicit focus")
    }

    /// T48: with background warm disabled, focusing a not-yet-connected window
    /// (windowDidBecomeKey) drives it to connected.
    @MainActor
    func testFocusTriggersConnectForOnDemandWindow() async throws {
        let path = "/tmp/redmargin-focus-\(UUID().uuidString).md"
        let location = RemoteLocation(host: "devtest", path: path)
        let (cache, cacheDir) = makeTempCache()
        defer {
            try? FileManager.default.removeItem(at: cacheDir)
            Task {
                _ = try? await ProcessRunner.run(
                    executable: "ssh", arguments: ["devtest", "rm -f \(path)"], timeout: 15
                )
            }
        }
        _ = try await ProcessRunner.run(
            executable: "ssh", arguments: ["devtest", "printf '# Focus\\n' > \(path)"], timeout: 15
        )

        let connection = await SSHConnectionManager.shared.preregisterConnection(for: "devtest")
        let state = RemoteDocumentState(
            content: "", location: location, fileProvider: RemoteFileProvider(connection: connection),
            connectsOnDemand: true, contentCache: cache
        )
        XCTAssertEqual(state.connectionPhase, .onDemand)

        let appDelegate = AppDelegate()
        let window = NSWindow()
        appDelegate.remoteDocumentWindows[location] = window

        // No background warm is started; simulate the window gaining focus.
        appDelegate.windowDidBecomeKey(
            Notification(name: NSWindow.didBecomeKeyNotification, object: window)
        )

        let connected = await waitUntil(timeout: 30) { state.connectionPhase == .connected }
        XCTAssertTrue(connected, "Focusing a not-yet-connected window connects it")
    }

    /// T49: an unreachable host fails fast into an inline unavailable state without a
    /// retry storm, keeping cached content visible. Uses a TEST-NET address that
    /// SYN-times-out (the same failure mode as a saved host that has gone off the
    /// network) to guard against the connection-timeout retry storm that turned one
    /// dead host into ~a minute. The exact error classification is covered
    /// deterministically by RemoteConnectRetryPolicyTests.
    @MainActor
    func testUnreachableHostFailsFastWithoutRetryStorm() async throws {
        let host = "192.0.2.\(Int.random(in: 2...250))"
        let location = RemoteLocation(host: host, path: "/tmp/dead.md")
        let (cache, cacheDir) = makeTempCache()
        defer {
            try? FileManager.default.removeItem(at: cacheDir)
            Task { await SSHConnectionManager.shared.disconnect(host: host) }
        }

        let connection = await SSHConnectionManager.shared.preregisterConnection(for: host)
        let state = RemoteDocumentState(
            content: "# Cached\n", location: location,
            fileProvider: RemoteFileProvider(connection: connection),
            connectsOnDemand: true, contentCache: cache
        )

        let start = Date()
        await state.connectIfNeeded()
        let elapsed = Date().timeIntervalSince(start)

        if case .unavailable = state.connectionPhase {} else {
            XCTFail("Unreachable host should resolve to an unavailable state, got \(state.connectionPhase)")
        }
        XCTAssertLessThan(elapsed, 15, "A timed-out host must fail in seconds, not storm with retries")
        XCTAssertEqual(state.content, "# Cached\n", "Cached content stays visible")
    }

    private func prepareSlowRemoteFIFO(
        path: String,
        writes: [(delay: Int, content: String)]
    ) async throws {
        _ = try await ProcessRunner.run(
            executable: "ssh",
            arguments: ["devtest", "rm -f \(path) && mkfifo \(path)"],
            timeout: 15
        )

        for write in writes {
            let content = write.content
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "'\\''")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            process.arguments = [
                "devtest",
                "sleep \(write.delay); printf '\(content)' > \(path)"
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            backgroundProcesses.append(process)
        }
    }

    override func tearDown() async throws {
        for process in backgroundProcesses where process.isRunning {
            process.terminate()
        }
        backgroundProcesses = []
        if let savedRecentWorkspacesData {
            UserDefaults.standard.set(savedRecentWorkspacesData, forKey: RecentWorkspaceStore.defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: RecentWorkspaceStore.defaultsKey)
        }
        savedRecentWorkspacesData = nil
        // Awaited cleanup of the shared devtest connection so on-demand tests, which
        // connect through SSHConnectionManager.shared, do not contaminate each other.
        await SSHConnectionManager.shared.disconnect(host: "devtest")
        try await super.tearDown()
    }
}

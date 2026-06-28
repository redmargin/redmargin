import XCTest
@testable import Redmargin
@testable import RedmarginLib
@testable import RedmarginCore

final class RemoteSidebarTests: XCTestCase {
    func testRemoteFileTreeProviderDoesNotEagerlyExpandTopLevelFoldersOnInitialLoad() async throws {
        let remoteProvider = TestRemoteTreeFileProvider(
            repoRoot: "/repo",
            directoryEntries: [
                "/repo": [
                    DirectoryEntry(name: "docs", isDirectory: true),
                    DirectoryEntry(name: "README.md", isDirectory: false)
                ],
                "/repo/docs": [
                    DirectoryEntry(name: "guide.md", isDirectory: false)
                ]
            ]
        )

        let provider = await RemoteFileTreeProvider(
            currentFilePath: "/repo/README.md",
            fileProvider: remoteProvider,
            expandedFoldersLoader: { _ in Set<String>() }
        )
        try await waitForRemoteProvider(provider)

        let rootNodes = await provider.rootNodes
        let docsNode = try XCTUnwrap(rootNodes.first { $0.name == "docs" })
        XCTAssertFalse(docsNode.isExpanded)
        XCTAssertFalse(docsNode.childrenLoaded)

        let listedPaths = await remoteProvider.recordedListPaths()
        XCTAssertEqual(listedPaths, ["/repo"])
    }

    func testRemoteDirectoryOpenKeepsOpenedFolderAsRootInsideRepo() async throws {
        let remoteProvider = TestRemoteTreeFileProvider(
            repoRoot: "/repo",
            directoryEntries: [
                "/repo": [
                    DirectoryEntry(name: "README.md", isDirectory: false),
                    DirectoryEntry(name: "emails", isDirectory: true)
                ],
                "/repo/emails": [
                    DirectoryEntry(name: "digest.md", isDirectory: false)
                ]
            ]
        )

        let provider = await RemoteFileTreeProvider(
            currentFilePath: "/repo/emails",
            fileProvider: remoteProvider,
            isDirectory: true,
            expandedFoldersLoader: { _ in Set<String>() }
        )
        try await waitForRemoteProvider(provider)

        let rootDirectory = await provider.rootDirectory
        let rootNodes = await provider.rootNodes
        let listedPaths = await remoteProvider.recordedListPaths()

        XCTAssertEqual(rootDirectory, "/repo/emails")
        XCTAssertEqual(rootNodes.map(\.name), ["digest.md"])
        XCTAssertEqual(listedPaths, ["/repo/emails"])
    }

    func testRemoteFileTreeProviderPreservesTildeRootPaths() async throws {
        let remoteProvider = TestRemoteTreeFileProvider(
            repoRoot: nil,
            directoryEntries: [
                "~/engagement": [
                    DirectoryEntry(name: "docs", isDirectory: true),
                    DirectoryEntry(name: "README.md", isDirectory: false)
                ],
                "~/engagement/docs": [
                    DirectoryEntry(name: "guide.md", isDirectory: false)
                ]
            ]
        )

        let provider = await RemoteFileTreeProvider(
            currentFilePath: "~/engagement",
            fileProvider: remoteProvider,
            isDirectory: true,
            expandedFoldersLoader: { _ in Set<String>() }
        )
        try await waitForRemoteProvider(provider)

        let rootNodes = await provider.rootNodes
        let docsNode = try XCTUnwrap(rootNodes.first { $0.name == "docs" })
        let readmeNode = try XCTUnwrap(rootNodes.first { $0.name == "README.md" })
        XCTAssertEqual(readmeNode.url.path, "~/engagement/README.md")
        XCTAssertEqual(docsNode.url.path, "~/engagement/docs")

        await MainActor.run {
            docsNode.isExpanded = true
        }

        try await waitUntil("tilde child path listed", timeout: 2) {
            let listedPaths = await remoteProvider.recordedListPaths()
            return listedPaths.contains("~/engagement/docs")
        }
    }

    func testRemoteFileTreeProviderRestoresNestedExpandedFoldersAfterInitialLoad() async throws {
        let remoteProvider = TestRemoteTreeFileProvider(
            repoRoot: "/repo",
            directoryEntries: [
                "/repo": [
                    DirectoryEntry(name: "folder", isDirectory: true),
                    DirectoryEntry(name: "README.md", isDirectory: false)
                ],
                "/repo/folder": [
                    DirectoryEntry(name: "sub", isDirectory: true)
                ],
                "/repo/folder/sub": [
                    DirectoryEntry(name: "child.md", isDirectory: false)
                ]
            ]
        )

        let provider = await RemoteFileTreeProvider(
            currentFilePath: "/repo/README.md",
            fileProvider: remoteProvider,
            expandedFoldersLoader: { _ in
                Set(["/repo/folder", "/repo/folder/sub"])
            }
        )
        try await waitForRemoteProvider(provider)
        try await waitUntil("remote nested expansion restore", timeout: 2) {
            let rootNodes = await provider.rootNodes
            guard let folderNode = rootNodes.first(where: { $0.name == "folder" }) else { return false }
            guard let subNode = folderNode.children.first(where: { $0.name == "sub" }) else { return false }
            return folderNode.isExpanded
                && subNode.isExpanded
                && subNode.children.contains(where: { $0.name == "child.md" })
        }
    }

    func testRemoteFileTreeProviderInitialLoadCompletesBeforeExpandedChildrenFinishLoading() async throws {
        let remoteProvider = TestRemoteTreeFileProvider(
            repoRoot: "/repo",
            directoryEntries: [
                "/repo": [
                    DirectoryEntry(name: "folder", isDirectory: true)
                ],
                "/repo/folder": [
                    DirectoryEntry(name: "sub", isDirectory: true)
                ],
                "/repo/folder/sub": [
                    DirectoryEntry(name: "child.md", isDirectory: false)
                ]
            ],
            listDelays: [
                "/repo/folder": 400_000_000,
                "/repo/folder/sub": 400_000_000
            ]
        )

        let start = Date()
        let provider = await RemoteFileTreeProvider(
            currentFilePath: "/repo/folder/sub/child.md",
            fileProvider: remoteProvider,
            expandedFoldersLoader: { _ in
                Set(["/repo/folder", "/repo/folder/sub"])
            }
        )

        try await waitUntil("remote root load completion", timeout: 1.0) {
            let isLoading = await provider.isLoading
            let rootNodes = await provider.rootNodes
            return !isLoading && !rootNodes.isEmpty
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(
            elapsed,
            0.35,
            "Initial remote load should finish before slow expanded-child restores complete"
        )

        try await waitUntil("remote expanded child loading", timeout: 2.0) {
            let listedPaths = await remoteProvider.recordedListPaths()
            return listedPaths.contains("/repo/folder/sub")
        }
    }

    func testRemoteFileTreeProviderReportsLoadErrorWhenRootListingFails() async throws {
        let remoteProvider = FailingRemoteTreeFileProvider()

        let provider = await RemoteFileTreeProvider(
            currentFilePath: "/repo",
            fileProvider: remoteProvider,
            isDirectory: true,
            expandedFoldersLoader: { _ in Set<String>() }
        )

        try await waitUntil("remote load failure", timeout: 2) {
            let isLoading = await provider.isLoading
            let loadError = await provider.loadError
            return !isLoading && loadError != nil
        }

        let rootNodes = await provider.rootNodes
        let loadError = await provider.loadError
        XCTAssertTrue(rootNodes.isEmpty)
        XCTAssertEqual(loadError, "Could not load the remote file list.")
    }

    // MARK: - Reconnect Tests

    func testRemoteSidebarReloadsOnMatchingReconnectNotification() async throws {
        let remoteProvider = TestRemoteTreeFileProvider(
            repoRoot: "/repo",
            directoryEntries: [
                "/repo": [
                    DirectoryEntry(name: "README.md", isDirectory: false)
                ]
            ]
        )

        let provider = await RemoteFileTreeProvider(
            currentFilePath: "/repo/README.md",
            fileProvider: remoteProvider,
            reconnectHost: "myhost",
            expandedFoldersLoader: { _ in Set<String>() }
        )
        try await waitForRemoteProvider(provider)

        let listCountBefore = await remoteProvider.recordedListPaths().count
        let watchCountBefore = await remoteProvider.recordedWatchPaths().count

        NotificationCenter.default.post(
            name: .sshConnectionReconnected,
            object: "myhost"
        )

        try await waitUntil("reconnect reload", timeout: 3) {
            let listCount = await remoteProvider.recordedListPaths().count
            return listCount > listCountBefore
        }

        let watchCountAfter = await remoteProvider.recordedWatchPaths().count
        XCTAssertGreaterThan(watchCountAfter, watchCountBefore, "Watches should be re-registered after reconnect")
    }

    func testRemoteSidebarIgnoresReconnectForOtherHost() async throws {
        let remoteProvider = TestRemoteTreeFileProvider(
            repoRoot: "/repo",
            directoryEntries: [
                "/repo": [
                    DirectoryEntry(name: "README.md", isDirectory: false)
                ]
            ]
        )

        let provider = await RemoteFileTreeProvider(
            currentFilePath: "/repo/README.md",
            fileProvider: remoteProvider,
            reconnectHost: "myhost",
            expandedFoldersLoader: { _ in Set<String>() }
        )
        try await waitForRemoteProvider(provider)

        let listCountBefore = await remoteProvider.recordedListPaths().count

        NotificationCenter.default.post(
            name: .sshConnectionReconnected,
            object: "otherhost"
        )

        // Wait briefly to ensure no reload triggers
        try await Task.sleep(nanoseconds: 300_000_000)

        let listCountAfter = await remoteProvider.recordedListPaths().count
        XCTAssertEqual(listCountAfter, listCountBefore, "Should not reload for a different host")
    }

    // MARK: - Refresh Tests

    func testRemoteSidebarRefreshCancelsPreviousRefresh() async throws {
        let remoteProvider = TestRemoteTreeFileProvider(
            repoRoot: "/repo",
            directoryEntries: [
                "/repo": [
                    DirectoryEntry(name: "first.md", isDirectory: false)
                ]
            ],
            listDelays: ["/repo": 500_000_000]  // 500ms delay
        )

        let provider = await RemoteFileTreeProvider(
            currentFilePath: "/repo/first.md",
            fileProvider: remoteProvider,
            expandedFoldersLoader: { _ in Set<String>() }
        )
        try await waitForRemoteProvider(provider)

        // Update entries for second refresh
        await remoteProvider.updateEntries([
            "/repo": [
                DirectoryEntry(name: "second.md", isDirectory: false)
            ]
        ])

        // Start first refresh (will be slow due to delay)
        await provider.refresh()

        // Immediately update entries again and trigger second refresh
        await remoteProvider.updateEntries([
            "/repo": [
                DirectoryEntry(name: "final.md", isDirectory: false)
            ]
        ])
        await provider.refresh()

        try await waitUntil("second refresh completes", timeout: 3) {
            let isLoading = await provider.isLoading
            return !isLoading
        }

        let rootNodes = await provider.rootNodes
        let names = rootNodes.map { $0.name }
        XCTAssertTrue(names.contains("final.md"), "Only the latest refresh should update rootNodes, got: \(names)")
    }

    func testRemoteSidebarRefreshTimeoutPreservesExistingTree() async throws {
        let remoteProvider = TestRemoteTreeFileProvider(
            repoRoot: "/repo",
            directoryEntries: [
                "/repo": [
                    DirectoryEntry(name: "README.md", isDirectory: false)
                ]
            ]
        )

        let provider = await RemoteFileTreeProvider(
            currentFilePath: "/repo/README.md",
            fileProvider: remoteProvider,
            expandedFoldersLoader: { _ in Set<String>() }
        )
        try await waitForRemoteProvider(provider)

        let nodesBefore = await provider.rootNodes
        XCTAssertFalse(nodesBefore.isEmpty)

        // Make list directory very slow and set short timeout
        await remoteProvider.updateEntries(["/repo": []])
        // listDelays can't be changed after init, so use a provider with built-in delay
        let slowProvider = TestRemoteTreeFileProvider(
            repoRoot: "/repo",
            directoryEntries: [
                "/repo": [
                    DirectoryEntry(name: "new.md", isDirectory: false)
                ]
            ],
            listDelays: ["/repo": 2_000_000_000]  // 2s delay
        )

        let providerWithTimeout = await RemoteFileTreeProvider(
            currentFilePath: "/repo/README.md",
            fileProvider: slowProvider,
            expandedFoldersLoader: { _ in Set<String>() }
        )
        try await waitForRemoteProvider(providerWithTimeout)

        // Set short timeout
        await MainActor.run { providerWithTimeout.refreshTimeout = 0.5 }

        // Trigger refresh — should timeout
        await providerWithTimeout.refresh()

        try await waitUntil("refresh timeout clears loading", timeout: 3) {
            let isLoading = await providerWithTimeout.isLoading
            return !isLoading
        }

        // Existing tree should be preserved (initial load nodes, not new.md which timed out)
        let nodesAfter = await providerWithTimeout.rootNodes
        XCTAssertFalse(nodesAfter.isEmpty, "Existing tree should be preserved on timeout")
    }

    func testRemoteSidebarRefreshReloadsExpandedVisibleFolders() async throws {
        let remoteProvider = TestRemoteTreeFileProvider(
            repoRoot: "/repo",
            directoryEntries: [
                "/repo": [
                    DirectoryEntry(name: "docs", isDirectory: true),
                    DirectoryEntry(name: "README.md", isDirectory: false)
                ],
                "/repo/docs": [
                    DirectoryEntry(name: "old.md", isDirectory: false)
                ]
            ]
        )

        let provider = await RemoteFileTreeProvider(
            currentFilePath: "/repo/README.md",
            fileProvider: remoteProvider,
            expandedFoldersLoader: { _ in Set(["/repo/docs"]) }
        )
        try await waitForRemoteProvider(provider)

        try await waitUntil("docs folder expanded", timeout: 2) {
            let rootNodes = await provider.rootNodes
            guard let docsNode = rootNodes.first(where: { $0.name == "docs" }) else { return false }
            return docsNode.isExpanded && docsNode.childrenLoaded
        }

        // Update the docs folder entries
        await remoteProvider.updateEntries([
            "/repo": [
                DirectoryEntry(name: "docs", isDirectory: true),
                DirectoryEntry(name: "README.md", isDirectory: false)
            ],
            "/repo/docs": [
                DirectoryEntry(name: "new.md", isDirectory: false)
            ]
        ])

        await provider.refresh()

        try await waitUntil("refresh completes with updated children", timeout: 3) {
            let isLoading = await provider.isLoading
            if isLoading { return false }
            let rootNodes = await provider.rootNodes
            guard let docsNode = rootNodes.first(where: { $0.name == "docs" }) else { return false }
            return docsNode.children.contains(where: { $0.name == "new.md" })
        }

        let rootNodes = await provider.rootNodes
        let docsNode = try XCTUnwrap(rootNodes.first { $0.name == "docs" })
        let childNames = docsNode.children.map { $0.name }
        XCTAssertTrue(childNames.contains("new.md"), "Expanded folder children should update on refresh")
    }

    func testRemoteSidebarRefreshSetsLoadingWhileActive() async throws {
        let remoteProvider = TestRemoteTreeFileProvider(
            repoRoot: "/repo",
            directoryEntries: [
                "/repo": [
                    DirectoryEntry(name: "README.md", isDirectory: false)
                ]
            ],
            listDelays: ["/repo": 300_000_000]  // 300ms delay
        )

        let provider = await RemoteFileTreeProvider(
            currentFilePath: "/repo/README.md",
            fileProvider: remoteProvider,
            expandedFoldersLoader: { _ in Set<String>() }
        )
        try await waitForRemoteProvider(provider)

        await provider.refresh()

        // isLoading should be true immediately after refresh()
        let loadingDuringRefresh = await provider.isLoading
        XCTAssertTrue(loadingDuringRefresh, "isLoading should be true during refresh")

        try await waitUntil("refresh completes", timeout: 3) {
            let isLoading = await provider.isLoading
            return !isLoading
        }

        let loadingAfterRefresh = await provider.isLoading
        XCTAssertFalse(loadingAfterRefresh, "isLoading should be false after refresh completes")
    }

    func testRemoteSidebarRefreshSelfHealsAfterTransientFailure() async throws {
        let remoteProvider = RecoveringRemoteTreeFileProvider(
            repoRoot: "/repo",
            initialEntries: [DirectoryEntry(name: "old.md", isDirectory: false)]
        )

        let provider = await RemoteFileTreeProvider(
            currentFilePath: "/repo/old.md",
            fileProvider: remoteProvider,
            expandedFoldersLoader: { _ in Set<String>() }
        )
        try await waitForRemoteProvider(provider)

        // The remote now has a new file, but the next listing (the refresh)
        // fails as if the SSH channel hiccuped mid-operation.
        await remoteProvider.setEntries([DirectoryEntry(name: "new.md", isDirectory: false)])
        await remoteProvider.setFailNextList(true)

        await provider.refresh()

        // The refresh fails, but the sidebar must self-heal via a reconnecting
        // reload instead of dead-ending at a manual Retry.
        try await waitUntil("sidebar self-heals to the updated tree", timeout: 8) {
            let isLoading = await provider.isLoading
            let names = await provider.rootNodes.map { $0.name }
            let loadError = await provider.loadError
            return !isLoading && loadError == nil && names.contains("new.md")
        }

        let names = await provider.rootNodes.map { $0.name }
        XCTAssertTrue(names.contains("new.md"), "Self-heal should reload the updated tree, got: \(names)")
        let loadError = await provider.loadError
        XCTAssertNil(loadError, "Self-heal should leave no error state behind")
    }

    private func waitForRemoteProvider(_ provider: RemoteFileTreeProvider, timeout: TimeInterval = 5) async throws {
        try await waitUntil("remote provider initial load", timeout: timeout) {
            let isLoading = await provider.isLoading
            let rootNodes = await provider.rootNodes
            return !isLoading && !rootNodes.isEmpty
        }
    }

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        check: @escaping () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !(await check()) {
            if Date() > deadline {
                XCTFail("Timed out waiting for \(description) after \(timeout)s")
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}

actor TestRemoteTreeFileProvider: RemoteFileTreeProviding {
    private let repoRoot: String?
    private(set) var directoryEntries: [String: [DirectoryEntry]]
    private let listDelays: [String: UInt64]
    private var listedPaths: [String] = []
    private var watchedPaths: [String] = []

    init(
        repoRoot: String?,
        directoryEntries: [String: [DirectoryEntry]],
        listDelays: [String: UInt64] = [:]
    ) {
        self.repoRoot = repoRoot
        self.directoryEntries = directoryEntries
        self.listDelays = listDelays
    }

    func detectGitRepo(for path: String) async throws -> String? {
        repoRoot
    }

    func gitStatus(for path: String) async throws -> GitStatusSnapshot {
        .empty
    }

    func listDirectory(at path: String) async throws -> [DirectoryEntry] {
        listedPaths.append(path)
        if let delay = listDelays[path] {
            try? await Task.sleep(nanoseconds: delay)
        }
        return directoryEntries[path] ?? []
    }

    func watchDirectory(at path: String, onChange: @escaping ([String]) -> Void) async -> WatchToken {
        watchedPaths.append(path)
        return UUID()
    }

    func unwatchDirectory(_ token: WatchToken) async {}

    func watchGitRepo(at repoRoot: String, onChange: @escaping () -> Void) async -> WatchToken {
        UUID()
    }

    func unwatch(_ token: WatchToken) async {}

    func recordedListPaths() -> [String] {
        listedPaths
    }

    func recordedWatchPaths() -> [String] {
        watchedPaths
    }

    func updateEntries(_ entries: [String: [DirectoryEntry]]) {
        directoryEntries = entries
    }
}

/// Lists successfully except when armed to fail the next listing once, modelling
/// a transient SSH-channel hiccup during a sidebar refresh.
actor RecoveringRemoteTreeFileProvider: RemoteFileTreeProviding {
    private let repoRoot: String?
    private var entries: [DirectoryEntry]
    private var failNextList = false

    init(repoRoot: String?, initialEntries: [DirectoryEntry]) {
        self.repoRoot = repoRoot
        self.entries = initialEntries
    }

    func setEntries(_ value: [DirectoryEntry]) { entries = value }
    func setFailNextList(_ value: Bool) { failNextList = value }

    func detectGitRepo(for path: String) async throws -> String? { repoRoot }

    func gitStatus(for path: String) async throws -> GitStatusSnapshot { .empty }

    func listDirectory(at path: String) async throws -> [DirectoryEntry] {
        if failNextList {
            failNextList = false
            throw RPCError.serverError("transient channel drop")
        }
        return entries
    }

    func watchDirectory(at path: String, onChange: @escaping ([String]) -> Void) async -> WatchToken { UUID() }

    func unwatchDirectory(_ token: WatchToken) async {}

    func watchGitRepo(at repoRoot: String, onChange: @escaping () -> Void) async -> WatchToken { UUID() }

    func unwatch(_ token: WatchToken) async {}
}

actor FailingRemoteTreeFileProvider: RemoteFileTreeProviding {
    func detectGitRepo(for path: String) async throws -> String? {
        nil
    }

    func gitStatus(for path: String) async throws -> GitStatusSnapshot {
        .empty
    }

    func listDirectory(at path: String) async throws -> [DirectoryEntry] {
        throw RPCError.serverError("stuck helper")
    }

    func watchDirectory(at path: String, onChange: @escaping ([String]) -> Void) async -> WatchToken {
        UUID()
    }

    func unwatchDirectory(_ token: WatchToken) async {}

    func watchGitRepo(at repoRoot: String, onChange: @escaping () -> Void) async -> WatchToken {
        UUID()
    }

    func unwatch(_ token: WatchToken) async {}
}

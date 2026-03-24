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
    private let directoryEntries: [String: [DirectoryEntry]]
    private let listDelays: [String: UInt64]
    private var listedPaths: [String] = []

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

    func listDirectory(at path: String) async throws -> [DirectoryEntry] {
        listedPaths.append(path)
        if let delay = listDelays[path] {
            try? await Task.sleep(nanoseconds: delay)
        }
        return directoryEntries[path] ?? []
    }

    func watchDirectory(at path: String, onChange: @escaping ([String]) -> Void) async -> WatchToken {
        UUID()
    }

    func unwatchDirectory(_ token: WatchToken) async {}

    func recordedListPaths() -> [String] {
        listedPaths
    }
}

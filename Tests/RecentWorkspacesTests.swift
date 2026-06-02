import XCTest
@testable import Redmargin
@testable import RedmarginCore

final class RecentWorkspacesTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var tempDir: URL!

    override func setUpWithError() throws {
        suiteName = "RecentWorkspacesTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecentWorkspacesTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
    }

    func testRecentWorkspaceItemRoundTripsLocalFile() throws {
        let file = tempDir.appendingPathComponent("notes.md")
        let date = Date(timeIntervalSince1970: 1_234)
        let item = RecentWorkspaceItem.localFile(file, lastOpened: date)
            .withPinned(true)

        let decoded = try JSONDecoder().decode(
            RecentWorkspaceItem.self,
            from: try JSONEncoder().encode(item)
        )

        XCTAssertEqual(decoded.kind, .localFile)
        XCTAssertEqual(decoded.displayTitle, "notes.md")
        XCTAssertEqual(decoded.locationText, tempDir.displayPath)
        XCTAssertTrue(decoded.isPinned)
        XCTAssertEqual(decoded.lastOpened, date)
    }

    func testRecentWorkspaceItemRoundTripsRemoteFolder() throws {
        let date = Date(timeIntervalSince1970: 2_468)
        let item = RecentWorkspaceItem.remoteFolder(
            RemoteLocation(host: "prod", path: "/var/www/"),
            lastOpened: date
        ).withPinned(true)

        let decoded = try JSONDecoder().decode(
            RecentWorkspaceItem.self,
            from: try JSONEncoder().encode(item)
        )

        XCTAssertEqual(decoded.kind, .remoteFolder)
        XCTAssertEqual(decoded.remoteLocation?.host, "prod")
        XCTAssertEqual(decoded.remoteLocation?.path, "/var/www/")
        XCTAssertEqual(decoded.kindLabel, "Folder")
        XCTAssertTrue(decoded.isPinned)
        XCTAssertEqual(decoded.lastOpened, date)
    }

    func testRecentWorkspaceStoreMigratesExistingFolderRecents() throws {
        let folder = tempDir.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let legacy = [LegacyRecentFolderItem(kind: .local, path: folder.path, host: nil)]
        defaults.set(try JSONEncoder().encode(legacy), forKey: "RedMargin.RecentFolders")

        let store = RecentWorkspaceStore(defaults: defaults)

        XCTAssertEqual(store.items.first?.kind, .localFolder)
        XCTAssertEqual(store.items.first?.localURL, folder.standardizedFileURL)
        XCTAssertNil(defaults.object(forKey: "RedMargin.RecentFolders"))
    }

    func testRecentWorkspaceStoreMigratesLegacyMixedRecents() throws {
        let file = tempDir.appendingPathComponent("a.md")
        let folder = tempDir.appendingPathComponent("folder")
        defaults.set([file.path], forKey: "RedMargin.RecentDocumentURLs")
        defaults.set([folder.path], forKey: "RedMargin.RecentFolderURLs")

        let store = RecentWorkspaceStore(defaults: defaults)

        XCTAssertTrue(store.items.contains { $0.kind == .localFile && $0.localURL == file.standardizedFileURL })
        XCTAssertTrue(store.items.contains { $0.kind == .localFolder && $0.localURL == folder.standardizedFileURL })
        XCTAssertNil(defaults.object(forKey: "RedMargin.RecentDocumentURLs"))
        XCTAssertNil(defaults.object(forKey: "RedMargin.RecentFolderURLs"))
    }

    func testRecentWorkspaceStoreMigratesLegacyRemoteRecents() throws {
        let location = RemoteLocation(host: "prod", path: "/srv/app/")
        defaults.set(try JSONEncoder().encode([location]), forKey: "RedMargin.RecentRemoteLocations")

        let store = RecentWorkspaceStore(defaults: defaults)

        XCTAssertEqual(store.items.first?.kind, .remoteFolder)
        XCTAssertEqual(store.items.first?.remoteLocation?.path, "/srv/app/")
        XCTAssertNil(defaults.object(forKey: "RedMargin.RecentRemoteLocations"))
    }

    func testRecentWorkspaceStoreLeavesRecentRemoteConnectionsAlone() throws {
        defaults.set(["prod"], forKey: "RedMargin.RecentRemoteConnections")
        defaults.set(
            try JSONEncoder().encode([RemoteLocation(host: "prod", path: "/srv/")]),
            forKey: "RedMargin.RecentRemoteLocations"
        )

        _ = RecentWorkspaceStore(defaults: defaults)

        XCTAssertEqual(defaults.stringArray(forKey: "RedMargin.RecentRemoteConnections"), ["prod"])
    }

    func testRecentWorkspaceStoreDeduplicatesByStorageKey() {
        let store = RecentWorkspaceStore(defaults: defaults)
        let file = tempDir.appendingPathComponent("same.md")

        store.add(.localFile(file, lastOpened: Date(timeIntervalSince1970: 1)))
        store.add(.localFile(file, lastOpened: Date(timeIntervalSince1970: 2)))

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.lastOpened, Date(timeIntervalSince1970: 2))
    }

    func testRecentWorkspaceStoreRetainsPinnedEntriesAboveRecents() {
        let store = RecentWorkspaceStore(defaults: defaults)
        let oldPinned = RecentWorkspaceItem.localFolder(
            tempDir.appendingPathComponent("pinned"),
            lastOpened: Date(timeIntervalSince1970: 1)
        ).withPinned(true)
        let newRecent = RecentWorkspaceItem.localFolder(
            tempDir.appendingPathComponent("recent"),
            lastOpened: Date(timeIntervalSince1970: 2)
        )

        store.add(newRecent)
        store.add(oldPinned)

        XCTAssertEqual((store.pinned + store.recent).first?.storageKey, oldPinned.storageKey)
        XCTAssertEqual(store.recent.first?.storageKey, newRecent.storageKey)
    }

    func testRecentWorkspaceStoreEnforcesRetentionForUnpinnedEntries() {
        let store = RecentWorkspaceStore(defaults: defaults)
        let pinned = RecentWorkspaceItem.localFolder(tempDir.appendingPathComponent("pinned")).withPinned(true)
        store.add(pinned)

        for index in 0...20 {
            let item = RecentWorkspaceItem.localFile(
                tempDir.appendingPathComponent("file-\(index).md"),
                lastOpened: Date(timeIntervalSince1970: TimeInterval(index))
            )
            store.add(item)
        }

        XCTAssertEqual(store.recent.count, RecentWorkspaceStore.defaultMaxUnpinnedItems)
        XCTAssertTrue(store.pinned.contains { $0.storageKey == pinned.storageKey })
        XCTAssertFalse(store.items.contains { $0.displayTitle == "file-0.md" })
    }

    func testRecentWorkspaceStoreSearchesNameAndLocation() {
        let store = RecentWorkspaceStore(defaults: defaults)
        store.add(.localFolder(URL(fileURLWithPath: "/tmp/logs")))
        store.add(.localFile(URL(fileURLWithPath: "/var/log/notes.md")))
        store.add(.remoteFile(RemoteLocation(host: "prod-logs", path: "/home/readme.md")))
        store.add(.remoteFolder(RemoteLocation(host: "prod", path: "/var/log/")))

        let result = store.filtered(search: "log", tier: .all, kind: .all, pinnedOnly: false)

        XCTAssertEqual(result.count, 4)
    }

    func testRecentWorkspaceStoreFiltersLocalAndRemote() {
        let store = fixtureStore()

        XCTAssertEqual(store.filtered(search: "", tier: .local, kind: .all, pinnedOnly: false).count, 2)
        XCTAssertEqual(store.filtered(search: "", tier: .remote, kind: .all, pinnedOnly: false).count, 2)
        XCTAssertEqual(store.filtered(search: "", tier: .all, kind: .all, pinnedOnly: false).count, 4)
    }

    func testRecentWorkspaceStoreFiltersFilesAndFolders() {
        let store = fixtureStore()

        XCTAssertEqual(store.filtered(search: "", tier: .all, kind: .files, pinnedOnly: false).count, 2)
        XCTAssertEqual(store.filtered(search: "", tier: .all, kind: .folders, pinnedOnly: false).count, 2)
        XCTAssertEqual(store.filtered(search: "", tier: .all, kind: .all, pinnedOnly: false).count, 4)
    }

    func testRecentWorkspaceStorePinOnlyFilter() {
        let store = fixtureStore()
        let item = store.items.first!
        store.pin(item)

        let result = store.filtered(search: "", tier: .all, kind: .all, pinnedOnly: true)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.storageKey, item.storageKey)
    }

    func testClearMissingRemovesOnlyUnavailableLocalEntries() throws {
        let store = RecentWorkspaceStore(defaults: defaults)
        let existing = tempDir.appendingPathComponent("existing.md")
        try "ok".write(to: existing, atomically: true, encoding: .utf8)
        let missing = tempDir.appendingPathComponent("missing.md")
        let remote = RemoteLocation(host: "prod", path: "/missing.md")

        store.add(.localFile(existing))
        store.add(.localFile(missing))
        store.add(.remoteFile(remote))
        store.clearMissingLocal()

        XCTAssertTrue(store.items.contains { $0.localURL == existing.standardizedFileURL })
        XCTAssertFalse(store.items.contains { $0.localURL == missing.standardizedFileURL })
        XCTAssertTrue(store.items.contains { $0.remoteLocation == remote })
    }

    func testRemoveDeletesOneWorkspace() {
        let store = fixtureStore()
        let item = store.items.first!

        store.remove(item)

        XCTAssertFalse(store.items.contains { $0.storageKey == item.storageKey })
        XCTAssertEqual(store.items.count, 3)
    }

    func testClearAllRemovesEverything() {
        let store = fixtureStore()

        store.clearAll()

        XCTAssertTrue(store.items.isEmpty)
    }

    func testMarkRemoteFailurePersistsReasonAndClearsOnRetrySuccess() {
        let store = RecentWorkspaceStore(defaults: defaults)
        let item = RecentWorkspaceItem.remoteFile(RemoteLocation(host: "prod", path: "/a.md"))
        store.add(item)

        store.markRemoteFailure(item, reason: "No route")
        XCTAssertEqual(store.items.first?.lastFailureReason, "No route")

        store.clearRemoteFailure(item)
        XCTAssertNil(store.items.first?.lastFailureReason)
    }

    func testRelocateReplacesLocationAndClearsFailure() {
        let store = RecentWorkspaceStore(defaults: defaults)
        let item = RecentWorkspaceItem(
            kind: .localFile,
            location: .local(tempDir.appendingPathComponent("old.md")),
            lastFailureReason: "missing"
        )
        let newURL = tempDir.appendingPathComponent("new.md")
        store.add(item)

        store.relocate(item, to: newURL)

        XCTAssertEqual(store.items.first?.localURL, newURL.standardizedFileURL)
        XCTAssertNil(store.items.first?.lastFailureReason)
    }

    func testStoreNeverDropsItemsForMissingTargets() {
        let missing = tempDir.appendingPathComponent("gone.md")
        var item = RecentWorkspaceItem.localFile(missing)
        item.lastOpened = Date(timeIntervalSince1970: 3)
        defaults.set(try! JSONEncoder().encode([item]), forKey: RecentWorkspaceStore.defaultsKey)

        let store = RecentWorkspaceStore(defaults: defaults)

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.localURL, missing.standardizedFileURL)
    }

    private func fixtureStore() -> RecentWorkspaceStore {
        let store = RecentWorkspaceStore(defaults: defaults)
        store.add(.localFile(tempDir.appendingPathComponent("local.md")))
        store.add(.localFolder(tempDir.appendingPathComponent("local-folder")))
        store.add(.remoteFile(RemoteLocation(host: "prod", path: "/file.md")))
        store.add(.remoteFolder(RemoteLocation(host: "prod", path: "/folder/")))
        return store
    }
}

private struct LegacyRecentFolderItem: Codable {
    enum Kind: String, Codable {
        case local
        case remote
    }

    let kind: Kind
    let path: String
    let host: String?
}

private extension RecentWorkspaceItem {
    func withPinned(_ pinned: Bool) -> RecentWorkspaceItem {
        var copy = self
        copy.isPinned = pinned
        return copy
    }
}

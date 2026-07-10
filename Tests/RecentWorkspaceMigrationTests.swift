import XCTest
@testable import Redmargin
@testable import RedmarginCore

/// CLAUDE.md: "Forward migrations never delete data." The recent-workspace
/// migration folds four legacy keys into one, and used to delete them, which left
/// an older build with nothing to read and no way back.
final class RecentWorkspaceMigrationTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    private let recentFoldersKey = "RedMargin.RecentFolders"
    private let legacyRecentURLsKey = "RedMargin.RecentDocumentURLs"
    private let legacyRecentFolderURLsKey = "RedMargin.RecentFolderURLs"
    private let legacyRecentRemoteLocationsKey = "RedMargin.RecentRemoteLocations"

    private var legacyKeys: [String] {
        [recentFoldersKey, legacyRecentURLsKey, legacyRecentFolderURLsKey, legacyRecentRemoteLocationsKey]
    }

    override func setUpWithError() throws {
        suiteName = "RecentWorkspaceMigrationTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    /// Seeds all four legacy sources.
    private func seedLegacyDefaults() throws {
        struct LegacyFolder: Codable {
            let kind: String
            let path: String
            let host: String?
        }
        let folders = [
            LegacyFolder(kind: "local", path: "/tmp/legacy-folder", host: nil),
            LegacyFolder(kind: "remote", path: "/srv/notes/", host: "devtest")
        ]
        defaults.set(try JSONEncoder().encode(folders), forKey: recentFoldersKey)
        defaults.set(["/tmp/legacy-doc.md"], forKey: legacyRecentURLsKey)
        defaults.set(["/tmp/legacy-folder-url"], forKey: legacyRecentFolderURLsKey)

        let locations = [RemoteLocation(host: "devtest", path: "/srv/remote-legacy/")]
        defaults.set(try JSONEncoder().encode(locations), forKey: legacyRecentRemoteLocationsKey)
    }

    /// The regression: an older build reads the legacy keys, and deleting them made
    /// the upgrade one-way.
    func testMigrationPreservesEveryLegacySourceKey() throws {
        try seedLegacyDefaults()

        _ = RecentWorkspaceStore(defaults: defaults)

        for key in legacyKeys {
            XCTAssertNotNil(defaults.object(forKey: key), "Migration deleted the legacy key \(key)")
        }
    }

    func testMigrationImportsEveryLegacySource() throws {
        try seedLegacyDefaults()

        let store = RecentWorkspaceStore(defaults: defaults)

        XCTAssertTrue(store.items.contains { $0.kind == .localFolder && $0.localURL?.path == "/tmp/legacy-folder" })
        XCTAssertTrue(store.items.contains { $0.kind == .localFile && $0.localURL?.path == "/tmp/legacy-doc.md" })
        XCTAssertTrue(store.items.contains { $0.kind == .localFolder && $0.localURL?.path == "/tmp/legacy-folder-url" })
        XCTAssertTrue(store.items.contains { $0.kind == .remoteFolder && $0.remoteLocation?.host == "devtest" })
    }

    /// Because the keys survive, the migration must not import them twice. That is
    /// what the recorded completion version is for.
    func testMigrationDoesNotReimportOnASecondLaunch() throws {
        try seedLegacyDefaults()

        let firstLaunch = RecentWorkspaceStore(defaults: defaults)
        let countAfterFirstLaunch = firstLaunch.items.count
        XCTAssertGreaterThan(countAfterFirstLaunch, 0)

        let secondLaunch = RecentWorkspaceStore(defaults: defaults)

        XCTAssertEqual(
            secondLaunch.items.count,
            countAfterFirstLaunch,
            "The legacy keys were imported a second time"
        )
    }

    /// The consequence that matters: the legacy keys now outlive the migration, so
    /// without the recorded completion an entry the user deleted would be imported
    /// again and reappear on the next launch.
    func testDeletedEntryDoesNotComeBackOnTheNextLaunch() throws {
        try seedLegacyDefaults()

        let firstLaunch = RecentWorkspaceStore(defaults: defaults)
        let doomed = try XCTUnwrap(firstLaunch.items.first { $0.localURL?.path == "/tmp/legacy-doc.md" })
        firstLaunch.remove(doomed)
        XCTAssertFalse(firstLaunch.items.contains { $0.localURL?.path == "/tmp/legacy-doc.md" })

        let secondLaunch = RecentWorkspaceStore(defaults: defaults)

        XCTAssertFalse(
            secondLaunch.items.contains { $0.localURL?.path == "/tmp/legacy-doc.md" },
            "A deleted recent entry was re-imported from the legacy keys"
        )
    }

    /// Completion is recorded even when there is nothing to migrate, so a fresh
    /// install does not re-scan the legacy keys on every launch.
    func testMigrationIsRecordedEvenWithNothingToImport() {
        _ = RecentWorkspaceStore(defaults: defaults)

        XCTAssertEqual(
            defaults.integer(forKey: RecentWorkspaceMigrator.migrationVersionKey),
            RecentWorkspaceMigrator.currentMigrationVersion
        )
    }

    /// A user who already migrated under the old build (keys deleted) is left alone.
    func testAlreadyMigratedInstallIsUntouched() throws {
        defaults.set(RecentWorkspaceMigrator.currentMigrationVersion, forKey: RecentWorkspaceMigrator.migrationVersionKey)
        try seedLegacyDefaults()

        let store = RecentWorkspaceStore(defaults: defaults)

        XCTAssertTrue(store.items.isEmpty, "A completed migration ran again")
        for key in legacyKeys {
            XCTAssertNotNil(defaults.object(forKey: key), "A completed migration deleted the legacy key \(key)")
        }
    }
}

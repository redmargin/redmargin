import XCTest
import RedmarginCore
@testable import Redmargin

final class PaletteSearchTests: XCTestCase {
    private let wraithFile = RecentWorkspaceItem.remoteFile(
        RemoteLocation(host: "wraith", path: "/Users/ghost/engagement/deliverables/Details Prep.md")
    )

    func testEveryTokenMustMatchSomeField() {
        XCTAssertNotNil(PaletteSearchQuery("wraith prep").score(wraithFile))
        XCTAssertNil(PaletteSearchQuery("wraith zzz").score(wraithFile))
    }

    func testHostPrefixMatchesRemoteItems() {
        XCTAssertNotNil(PaletteSearchQuery("wra").score(wraithFile))
    }

    func testLocalItemsMatchByRepoFolderInPath() {
        let item = RecentWorkspaceItem.localFile(
            URL(fileURLWithPath: "/Users/marco/dev/redmargin/resources/docs/notes.md")
        )
        XCTAssertNotNil(PaletteSearchQuery("redmargin notes").score(item))
        XCTAssertNil(PaletteSearchQuery("redmargin missing").score(item))
    }

    func testEmptyQueryScoresZeroAndMatchesEverything() {
        XCTAssertEqual(PaletteSearchQuery("  ").score(wraithFile), 0)
    }

    func testStoreFilteredRanksHostMatchAboveTitleSubstringMatch() {
        let suiteName = "PaletteSearchTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let hostItem = RecentWorkspaceItem.remoteFolder(
            RemoteLocation(host: "spamnesia-dev", path: "/opt/app/"),
            lastOpened: Date(timeIntervalSinceNow: -3600)
        )
        let titleItem = RecentWorkspaceItem.localFile(
            URL(fileURLWithPath: "/tmp/notes/spamnesia-clippings.md"),
            lastOpened: Date()
        )

        let store = RecentWorkspaceStore(defaults: defaults)
        store.add(hostItem)
        store.add(titleItem)

        let results = store.filtered(search: "spamnesia", tier: .all, kind: .all, pinnedOnly: false)
        XCTAssertEqual(results.map(\.storageKey), [hostItem.storageKey, titleItem.storageKey])
    }

    func testStoreFilteredUsesTokenizedSearch() {
        let suiteName = "PaletteSearchTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = RecentWorkspaceStore(defaults: defaults)
        store.add(wraithFile)
        store.add(.localFile(URL(fileURLWithPath: "/tmp/other.md")))

        let results = store.filtered(search: "wraith prep", tier: .all, kind: .all, pinnedOnly: false)
        XCTAssertEqual(results.map(\.storageKey), [wraithFile.storageKey])
    }
}

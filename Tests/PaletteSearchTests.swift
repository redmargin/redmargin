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

    func testHostMatchOutranksPathSubstringMatch() async {
        let hostItem = RecentWorkspaceItem.remoteFolder(
            RemoteLocation(host: "spamnesia-dev", path: "/opt/app/"),
            lastOpened: Date(timeIntervalSinceNow: -3600)
        )
        let titleItem = RecentWorkspaceItem.localFile(
            URL(fileURLWithPath: "/tmp/notes/spamnesia-clippings.md"),
            lastOpened: Date()
        )

        let sections = await CommandPaletteSource().sections(
            workspaces: [titleItem, hostItem],
            search: "spamnesia",
            focus: .recents,
            hasActiveDocument: true
        )

        let recents = sections.first { $0.title == "Recent Workspaces" }
        guard case .workspace(let first) = recents?.entries.first else {
            return XCTFail("Expected a workspace entry, got \(String(describing: recents?.entries.first))")
        }
        XCTAssertEqual(first.storageKey, hostItem.storageKey)
    }

    func testTokenizedCommandMatching() async {
        let sections = await CommandPaletteSource().sections(
            workspaces: [],
            search: "toggle git",
            focus: .actions,
            hasActiveDocument: true
        )

        let commands = sections.flatMap(\.entries).compactMap { entry -> AppCommand? in
            if case .command(let command, _) = entry { return command }
            return nil
        }
        XCTAssertEqual(commands, [.toggleGitIndicators])
    }

    func testRemoteEntryShowsHostBadgeAndPathSubtitle() {
        let remote = CommandPaletteEntry.workspace(wraithFile)
        XCTAssertEqual(remote.hostBadge, "wraith")
        XCTAssertEqual(remote.subtitle, "/Users/ghost/engagement/deliverables/Details Prep.md")

        let local = CommandPaletteEntry.workspace(.localFile(URL(fileURLWithPath: "/tmp/a.md")))
        XCTAssertNil(local.hostBadge)
        XCTAssertEqual(local.subtitle, "/tmp")
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

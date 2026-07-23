import XCTest
import RedmarginCore
@testable import Redmargin

final class RecentWorkspacePresentationTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PresentationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        super.tearDown()
    }

    func testRepoSlugDerivation() {
        let home = FileManager.default.homeDirectoryForCurrentUser

        let nested = RecentWorkspaceItem.localFolder(home.appendingPathComponent("dev/detours"))
        XCTAssertEqual(nested.repoSlug, "dev/detours")

        let homeDirect = RecentWorkspaceItem.localFolder(home.appendingPathComponent("dotfiles"))
        XCTAssertEqual(homeDirect.repoSlug, "dotfiles")

        let localFile = RecentWorkspaceItem.localFile(URL(fileURLWithPath: "/tmp/notes/a.md"))
        XCTAssertEqual(localFile.repoSlug, "a.md")

        let remoteHomeFolder = RecentWorkspaceItem.remoteFolder(
            RemoteLocation(host: "wraith", path: "~/engagement/")
        )
        XCTAssertEqual(remoteHomeFolder.repoSlug, "engagement")

        let remoteNested = RecentWorkspaceItem.remoteFolder(
            RemoteLocation(host: "spamnesia-dev", path: "/opt/spamnesia/")
        )
        XCTAssertEqual(remoteNested.repoSlug, "opt/spamnesia")

        let remoteFile = RecentWorkspaceItem.remoteFile(
            RemoteLocation(host: "wraith", path: "/Users/ghost/engagement/deliverables/Details Prep.md")
        )
        XCTAssertEqual(remoteFile.repoSlug, "Details Prep.md")
    }

    func testMachineTokenIsHostOrNil() {
        let remote = RecentWorkspaceItem.remoteFolder(RemoteLocation(host: "wraith", path: "~/engagement/"))
        XCTAssertEqual(remote.machineToken, "wraith")

        let local = RecentWorkspaceItem.localFolder(tempDir)
        XCTAssertNil(local.machineToken)
    }

    func testMetaLineDecision() {
        let repoFolder = RecentWorkspaceItem.localFolder(tempDir)
        let summary = GitWorkspaceSummary(branch: "main", changedCount: 3)
        XCTAssertEqual(repoFolder.meta(gitSummary: summary), .git(branch: "main", changedCount: 3))
        XCTAssertNil(repoFolder.meta(gitSummary: nil))

        let remoteFolder = RecentWorkspaceItem.remoteFolder(
            RemoteLocation(host: "azooco-dev", path: "/opt/azooco/")
        )
        XCTAssertNil(remoteFolder.meta(gitSummary: nil))

        let remoteFile = RecentWorkspaceItem.remoteFile(
            RemoteLocation(host: "wraith", path: "~/engagement/report/deliverables/Details Prep.md")
        )
        XCTAssertEqual(
            remoteFile.meta(gitSummary: nil),
            .containingPath("~/engagement/report/deliverables/")
        )

        var failed = RecentWorkspaceItem.remoteFolder(RemoteLocation(host: "wraith", path: "~/gone/"))
        failed.lastFailureReason = "connection refused"
        failed.lastFailureDate = Date(timeIntervalSinceNow: -86_400)
        guard case .warning(let text)? = failed.meta(gitSummary: nil) else {
            return XCTFail("Expected a warning meta, got \(String(describing: failed.meta(gitSummary: nil)))")
        }
        XCTAssertTrue(text.hasPrefix("unreachable since"), "got: \(text)")

        let missing = RecentWorkspaceItem.localFile(tempDir.appendingPathComponent("gone.md"))
        XCTAssertEqual(missing.meta(gitSummary: nil), .warning("missing"))
    }

    func testAvailabilityDotMapping() {
        let present = RecentWorkspaceItem.localFolder(tempDir)
        XCTAssertEqual(present.availability(hasLiveConnection: false), .available)

        let missing = RecentWorkspaceItem.localFile(tempDir.appendingPathComponent("gone.md"))
        XCTAssertEqual(missing.availability(hasLiveConnection: false), .unavailable)

        var failed = RecentWorkspaceItem.remoteFolder(RemoteLocation(host: "wraith", path: "~/x/"))
        failed.lastFailureReason = "timeout"
        XCTAssertEqual(failed.availability(hasLiveConnection: true), .unavailable)

        let idle = RecentWorkspaceItem.remoteFolder(RemoteLocation(host: "wraith", path: "~/x/"))
        XCTAssertEqual(idle.availability(hasLiveConnection: false), .idle)
        XCTAssertEqual(idle.availability(hasLiveConnection: true), .available)
    }

    func testFailureBookkeepingCarriesDate() {
        let suiteName = "PresentationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = RecentWorkspaceStore(defaults: defaults)
        let item = RecentWorkspaceItem.remoteFolder(RemoteLocation(host: "wraith", path: "~/x/"))
        store.add(item)

        store.markRemoteFailure(item, reason: "timeout")
        XCTAssertNotNil(store.items.first?.lastFailureDate)

        store.clearRemoteFailure(item)
        XCTAssertNil(store.items.first?.lastFailureDate)
        XCTAssertNil(store.items.first?.lastFailureReason)
    }
}

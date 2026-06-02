import XCTest
@testable import Redmargin

final class RecentWorkspacesPolicyTests: XCTestCase {
    func testPolicyReturnsTrueOnEmptyLaunchWithSettingOn() {
        XCTAssertTrue(eligible())
    }

    func testPolicyReturnsFalseWhenLocalWindowRestored() {
        XCTAssertFalse(eligible(restoredLocalCount: 1))
    }

    func testPolicyReturnsFalseWhenRemoteWindowRestored() {
        XCTAssertFalse(eligible(restoredRemoteCount: 1))
    }

    func testPolicyReturnsFalseWhenFolderWindowRestored() {
        XCTAssertFalse(eligible(restoredFolderCount: 1))
    }

    func testPolicyReturnsFalseWhenLaunchedWithFiles() {
        XCTAssertFalse(eligible(launchedWithFiles: true))
    }

    func testPolicyReturnsFalseWhenPendingRemoteLaunches() {
        XCTAssertFalse(eligible(hasPendingRemoteLaunches: true))
    }

    func testPolicyReturnsFalseWhenSettingOff() {
        XCTAssertFalse(eligible(settingEnabled: false))
    }

    private func eligible(
        restoredLocalCount: Int = 0,
        restoredRemoteCount: Int = 0,
        restoredFolderCount: Int = 0,
        launchedWithFiles: Bool = false,
        hasPendingRemoteLaunches: Bool = false,
        settingEnabled: Bool = true
    ) -> Bool {
        RecentWorkspacesPolicy.shouldShowAtLaunch(
            restoredLocalCount: restoredLocalCount,
            restoredRemoteCount: restoredRemoteCount,
            restoredFolderCount: restoredFolderCount,
            launchedWithFiles: launchedWithFiles,
            hasPendingRemoteLaunches: hasPendingRemoteLaunches,
            settingEnabled: settingEnabled
        )
    }
}

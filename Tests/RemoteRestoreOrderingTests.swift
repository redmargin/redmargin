import XCTest
@testable import Redmargin
@testable import RedmarginCore

final class RemoteRestoreOrderingTests: XCTestCase {
    private func loc(_ path: String) -> RemoteLocation {
        RemoteLocation(host: "devtest", path: path)
    }

    func testRestoreOrderRebuildsSavedZOrder() {
        let a = loc("/a.md")
        let b = loc("/b.md")
        let c = loc("/c.md")

        // Saved back-to-front order is a (back), b, c (front); frontmost is b.
        let plan = RemoteRestoreOrdering.plan(
            locations: [c, a, b],  // arbitrary array order from the saved dictionary
            savedOrderKeys: [a.storageKey, b.storageKey, c.storageKey],
            frontmostKey: b.storageKey
        )

        XCTAssertEqual(plan.placementOrder, [a, b, c], "Placement follows saved back-to-front order")
        XCTAssertEqual(plan.keyLocation, b, "The saved frontmost is the single window to make key")
    }

    func testRestoreOrderFallsBackToArrayOrderWhenNoSavedOrder() {
        let a = loc("/a.md")
        let b = loc("/b.md")

        let plan = RemoteRestoreOrdering.plan(
            locations: [a, b],
            savedOrderKeys: [],
            frontmostKey: nil
        )

        XCTAssertEqual(plan.placementOrder, [a, b], "Falls back to the saved-array order")
        XCTAssertEqual(plan.keyLocation, b, "Last-placed (frontmost) window is key when none recorded")
    }

    func testWindowTokenStripsRemotePrefixToStorageKey() {
        let location = loc("/dir/file.md")
        let token = "remote:\(location.host):\(location.path)"
        XCTAssertEqual(RemoteRestoreOrdering.storageKey(fromWindowToken: token), location.storageKey)
        XCTAssertNil(RemoteRestoreOrdering.storageKey(fromWindowToken: "folder:/local/path"))
    }
}

import XCTest
@testable import RedmarginCore

/// App Nap prevention is reference counted on `SSHConnectionManager`. Nothing here needs
/// a remote host, so these live outside `SSHConnectionTests`, which `build.sh` skips as a
/// live-remote suite.
final class AppNapActivityTests: XCTestCase {

    /// The activity is reference counted: it starts on the first remote document and
    /// is released only when the last one closes.
    func testAppNapActivityIsHeldWhileAnyRemoteDocumentIsOpen() async throws {
        let manager = SSHConnectionManager.shared
        let initial = await manager.remoteDocumentActivityCount

        await manager.beginRemoteDocumentActivity()
        var count = await manager.remoteDocumentActivityCount
        XCTAssertEqual(count, initial + 1)
        var holding = await manager.isHoldingAppNapActivity
        XCTAssertTrue(holding, "An open remote document must hold the App Nap activity")

        await manager.beginRemoteDocumentActivity()
        count = await manager.remoteDocumentActivityCount
        XCTAssertEqual(count, initial + 2)

        await manager.endRemoteDocumentActivity()
        count = await manager.remoteDocumentActivityCount
        XCTAssertEqual(count, initial + 1, "One document closing must not release the activity")
        holding = await manager.isHoldingAppNapActivity
        XCTAssertTrue(holding, "The activity is held until the last document closes")

        await manager.endRemoteDocumentActivity()
        count = await manager.remoteDocumentActivityCount
        XCTAssertEqual(count, initial, "Balanced begin/end returns the count to where it started")
    }

    /// An unbalanced end must floor the count at zero rather than drive it negative,
    /// which would stop the next document from ever starting the activity.
    func testUnbalancedEndDoesNotDriveTheActivityCountNegative() async throws {
        let manager = SSHConnectionManager.shared

        await manager.endRemoteDocumentActivity()
        await manager.endRemoteDocumentActivity()
        let count = await manager.remoteDocumentActivityCount
        XCTAssertEqual(count, 0, "The refcount must floor at zero")

        // A document opened afterwards still starts the activity.
        await manager.beginRemoteDocumentActivity()
        let holding = await manager.isHoldingAppNapActivity
        XCTAssertTrue(holding, "A document opened after an unbalanced end must hold the activity")
        await manager.endRemoteDocumentActivity()
    }
}

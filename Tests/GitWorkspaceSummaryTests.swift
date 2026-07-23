import XCTest
@testable import RedmarginCore

final class GitWorkspaceSummaryTests: XCTestCase {
    private var helper: GitTestHelper!

    override func setUpWithError() throws {
        helper = GitTestHelper()
        try helper.setUp()
    }

    override func tearDown() {
        helper.tearDown()
        helper = nil
        super.tearDown()
    }

    func testSummaryOnRealRepo() async throws {
        let repo = try helper.createRepo(named: "workspace")
        try helper.createFile(named: "README.md", content: "# Hello\n", in: repo)
        try helper.commit(message: "initial", in: repo)

        let clean = await GitStatusProvider().summary(for: repo)
        XCTAssertNotNil(clean)
        XCTAssertEqual(clean?.changedCount, 0)
        XCTAssertFalse(clean?.branch.isEmpty ?? true)

        try helper.createFile(named: "README.md", content: "# Hello edited\n", in: repo)
        try helper.createFile(named: "new.md", content: "new\n", in: repo)

        let dirty = await GitStatusProvider().summary(for: repo)
        XCTAssertEqual(dirty?.changedCount, 2)
        XCTAssertEqual(dirty?.branch, clean?.branch)
    }

    func testSummaryOutsideRepo() async throws {
        let plain = try helper.createDirectory(named: "not-a-repo", in: helper.rootDirectory)

        let summary = await GitStatusProvider().summary(for: plain)
        XCTAssertNil(summary)
    }

    func testHasLiveConnectionDoesNotConnect() async {
        let manager = SSHConnectionManager.shared
        let startsBefore = await manager.connectStartCount

        let result = await manager.hasLiveConnection(host: "no-such-host-for-this-test")

        XCTAssertFalse(result)
        let startsAfter = await manager.connectStartCount
        XCTAssertEqual(startsAfter, startsBefore)
    }
}

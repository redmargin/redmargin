import XCTest
@testable import Redmargin

final class RemoteRefreshRoutingTests: XCTestCase {

    func testRemoteFolderCommandRefreshWithoutSelectionSkipsDocumentRefresh() {
        let route = remoteRefreshRoute(
            isFolderMode: true,
            sidebarVisible: false,
            source: .commandRefresh
        )
        XCTAssertEqual(route, .sidebarOnly)

        let routeWithSidebar = remoteRefreshRoute(
            isFolderMode: true,
            sidebarVisible: true,
            source: .commandRefresh
        )
        XCTAssertEqual(routeWithSidebar, .sidebarOnly)
    }

    func testRemoteFolderSidebarButtonRefreshWithoutSelectionSkipsDocumentRefresh() {
        let route = remoteRefreshRoute(
            isFolderMode: true,
            sidebarVisible: true,
            source: .sidebarButton
        )
        XCTAssertEqual(route, .sidebarOnly)
    }

    func testRemoteFolderCommandRefreshWithSelectionRefreshesDocumentAndVisibleSidebar() {
        let route = remoteRefreshRoute(
            isFolderMode: false,
            sidebarVisible: true,
            source: .commandRefresh
        )
        XCTAssertEqual(route, .documentAndSidebar)
    }

    func testRemoteFolderSidebarButtonRefreshWithSelectionRefreshesDocumentAndSidebar() {
        let route = remoteRefreshRoute(
            isFolderMode: false,
            sidebarVisible: true,
            source: .sidebarButton
        )
        XCTAssertEqual(route, .documentAndSidebar)
    }

    func testRemoteDocumentRefreshWithHiddenSidebarRefreshesDocumentOnly() {
        let route = remoteRefreshRoute(
            isFolderMode: false,
            sidebarVisible: false,
            source: .commandRefresh
        )
        XCTAssertEqual(route, .documentOnly)
    }

    func testRemoteDocumentRefreshWithVisibleSidebarRefreshesDocumentAndSidebar() {
        let route = remoteRefreshRoute(
            isFolderMode: false,
            sidebarVisible: true,
            source: .commandRefresh
        )
        XCTAssertEqual(route, .documentAndSidebar)
    }
}

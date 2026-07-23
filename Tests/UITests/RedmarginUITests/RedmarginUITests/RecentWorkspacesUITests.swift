import XCTest

/// Drives the real Recent Workspaces switcher: Cmd-P opens it, the opened test
/// file appears as a row with the fused-token accessibility shape, search
/// narrows it, and Return opens the selection and dismisses the window.
final class RecentWorkspacesUITests: BaseUITest {
    func testSwitcherShowsSearchesAndOpensARecentWorkspace() throws {
        // The base setup opened test.md, which records it as a recent workspace.
        pressCharKey("p", modifiers: .command)

        let switcher = app.windows["Recent Workspaces"]
        XCTAssertTrue(switcher.waitForExistence(timeout: 5), "Cmd-P should open the Recent Workspaces window")

        let rowLabel = "test.md on this Mac, file"
        let row = switcher.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", rowLabel)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "The opened file should appear as a recent row")

        // The search field has focus on open; a query keeps the matching row.
        app.typeText("test")
        XCTAssertTrue(row.waitForExistence(timeout: 3), "Searching for the file should keep its row visible")

        // Return opens the selected row and closes the switcher.
        pressKey(.return)
        let deadline = Date().addingTimeInterval(8)
        while switcher.exists && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTAssertFalse(switcher.exists, "Opening the selection should dismiss the switcher")

        let documentWindow = app.windows.matching(
            NSPredicate(format: "title CONTAINS %@", "test.md")
        ).firstMatch
        XCTAssertTrue(documentWindow.waitForExistence(timeout: 8), "The opened workspace should surface its document window")
    }
}

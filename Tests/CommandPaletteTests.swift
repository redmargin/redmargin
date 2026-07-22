import XCTest
@testable import Redmargin

final class CommandPaletteTests: XCTestCase {
    func testCommandPaletteListsAllAppCommands() async {
        let entries = await sourceEntries()

        XCTAssertEqual(entries.map(\.command), AppCommand.allCases)
    }

    func testCommandPaletteSearchFiltersCommands() async {
        let entries = await sourceEntries(search: "side")

        XCTAssertTrue(entries.contains { $0.command == .toggleSidebar })
        XCTAssertFalse(entries.contains { $0.command == .openFile })
    }

    func testCommandPaletteMatchesMultiTokenQueries() async {
        let entries = await sourceEntries(search: "toggle git")

        XCTAssertEqual(entries.map(\.command), [.toggleGitIndicators])
    }

    func testCommandPaletteDispatchesMenuBackedCommand() {
        let appDelegate = AppDelegate()
        let expectation = expectation(description: "toggleSidebar notification")
        let observer = NotificationCenter.default.addObserver(
            forName: .toggleSidebar,
            object: nil,
            queue: .main
        ) { _ in
            expectation.fulfill()
        }

        AppCommand.toggleSidebar.handler(appDelegate: appDelegate)()

        wait(for: [expectation], timeout: 1)
        NotificationCenter.default.removeObserver(observer)
    }

    func testCommandPaletteDisablesDocumentOnlyCommandsWithoutDocument() async {
        let entries = await sourceEntries(hasActiveDocument: false)

        XCTAssertTrue(entries.contains { $0.command == .toggleSidebar && !$0.isEnabled })
        XCTAssertTrue(entries.contains { $0.command == .openFile && $0.isEnabled })
    }

    func testRecentWorkspacesOwnsCommandPShortcut() {
        XCTAssertEqual(AppCommand.recentWorkspaces.keyEquivalent, "⌘P")
        XCTAssertEqual(AppCommand.commandPalette.keyEquivalent, "⇧⌘P")
    }

    private func sourceEntries(
        search: String = "",
        hasActiveDocument: Bool = true
    ) async -> [CommandPaletteEntry] {
        await CommandPaletteSource().entries(
            search: search,
            hasActiveDocument: hasActiveDocument
        )
    }
}

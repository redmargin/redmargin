import XCTest
@testable import Redmargin

final class CommandPaletteTests: XCTestCase {
    func testCommandPaletteIncludesRecentWorkspaces() async {
        let workspace = RecentWorkspaceItem.localFile(URL(fileURLWithPath: "/tmp/Sidebar.md"))
        let sections = await sourceSections(workspaces: [workspace])

        XCTAssertTrue(sections.flatMap(\.entries).contains { entry in
            if case .workspace(let item) = entry {
                return item.storageKey == workspace.storageKey
            }
            return false
        })
    }

    func testCommandPaletteIncludesAppCommands() async {
        let sections = await sourceSections()
        let commandCount = sections.flatMap(\.entries).filter { entry in
            if case .command = entry { return true }
            return false
        }.count

        XCTAssertEqual(commandCount, AppCommand.allCases.count)
    }

    func testCommandPaletteSearchMatchesRecentAndCommands() async {
        let workspace = RecentWorkspaceItem.localFile(URL(fileURLWithPath: "/tmp/Sidebar.md"))
        let sections = await sourceSections(workspaces: [workspace], search: "side")
        let entries = sections.flatMap(\.entries)

        XCTAssertTrue(entries.contains { entry in
            if case .workspace(let item) = entry {
                return item.displayTitle == "Sidebar.md"
            }
            return false
        })
        XCTAssertTrue(entries.contains { entry in
            if case .command(let command, _) = entry {
                return command == .toggleSidebar
            }
            return false
        })
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
        let sections = await sourceSections(hasActiveDocument: false)

        XCTAssertTrue(sections.flatMap(\.entries).contains { entry in
            if case .command(.toggleSidebar, let isEnabled) = entry {
                return !isEnabled
            }
            return false
        })
    }

    func testCommandPaletteRecentsFocusOrdersRecentsFirst() async {
        let sections = await sourceSections(
            workspaces: [.localFile(URL(fileURLWithPath: "/tmp/a.md"))],
            focus: .recents
        )

        XCTAssertEqual(sections.first?.title, "Recent Workspaces")
    }

    func testCommandPaletteActionsFocusOrdersActionsFirst() async {
        let sections = await sourceSections(
            workspaces: [.localFile(URL(fileURLWithPath: "/tmp/a.md"))],
            focus: .actions
        )

        XCTAssertEqual(sections.first?.title, "Actions")
    }

    private func sourceSections(
        workspaces: [RecentWorkspaceItem] = [],
        search: String = "",
        focus: CommandPaletteFocus = .recents,
        hasActiveDocument: Bool = true
    ) async -> [CommandPaletteSection] {
        await CommandPaletteSource().sections(
            workspaces: workspaces,
            search: search,
            focus: focus,
            hasActiveDocument: hasActiveDocument
        )
    }
}

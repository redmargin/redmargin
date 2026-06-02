import AppKit
import XCTest
@testable import Redmargin
@testable import RedmarginCore

@MainActor
final class MainMenuTests: XCTestCase {
    private var savedRecentWorkspaces: Data?

    override func setUp() {
        super.setUp()
        savedRecentWorkspaces = UserDefaults.standard.data(forKey: RecentWorkspaceStore.defaultsKey)
        UserDefaults.standard.removeObject(forKey: RecentWorkspaceStore.defaultsKey)
    }

    override func tearDown() {
        if let savedRecentWorkspaces {
            UserDefaults.standard.set(savedRecentWorkspaces, forKey: RecentWorkspaceStore.defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: RecentWorkspaceStore.defaultsKey)
        }
        savedRecentWorkspaces = nil
        NSApp.mainMenu = nil
        super.tearDown()
    }

    func testFileMenuRecentWorkspaceAndPaletteShortcuts() {
        let appDelegate = AppDelegate()

        setupMainMenu(target: appDelegate)

        let fileMenu = NSApp.mainMenu?.item(withTitle: "File")?.submenu
        XCTAssertNotNil(fileMenu)
        let recentWorkspaces = fileMenu?.item(withTitle: "Recent Workspaces...")
        XCTAssertEqual(recentWorkspaces?.keyEquivalent, "1")
        XCTAssertEqual(recentWorkspaces?.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask), [.command, .shift])

        let commandPalette = fileMenu?.item(withTitle: "Command Palette")
        XCTAssertEqual(commandPalette?.keyEquivalent, "p")
        XCTAssertEqual(commandPalette?.representedObject as? CommandPaletteFocus, .recents)

        let commandPaletteActions = fileMenu?.item(withTitle: "Command Palette — Actions")
        XCTAssertEqual(commandPaletteActions?.keyEquivalent, "P")
        XCTAssertEqual(commandPaletteActions?.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask), [.command, .shift])
        XCTAssertEqual(commandPaletteActions?.representedObject as? CommandPaletteFocus, .actions)

        let print = fileMenu?.item(withTitle: "Print...")
        XCTAssertEqual(print?.keyEquivalent, "p")
        XCTAssertEqual(print?.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask), [.command, .option])
    }

    func testOpenRecentMenuShowsTenRecentWorkspacesAndClearMenu() {
        let appDelegate = AppDelegate()
        for index in 0..<12 {
            let item = RecentWorkspaceItem.localFile(
                URL(fileURLWithPath: "/tmp/recent-\(index).md"),
                lastOpened: Date(timeIntervalSince1970: TimeInterval(index))
            )
            appDelegate.recentWorkspaces.add(item)
        }

        setupMainMenu(target: appDelegate)
        let openRecent = NSApp.mainMenu?
            .item(withTitle: "File")?
            .submenu?
            .item(withTitle: "Open Recent")?
            .submenu
        XCTAssertNotNil(openRecent)

        (openRecent?.delegate as? OpenRecentMenuDelegate)?.menuNeedsUpdate(openRecent!)

        let titles = openRecent?.items.map(\.title) ?? []
        XCTAssertEqual(titles.filter { $0.hasPrefix("recent-") }.count, 10)
        XCTAssertTrue(titles.contains("recent-11.md"))
        XCTAssertTrue(titles.contains("recent-2.md"))
        XCTAssertFalse(titles.contains("recent-0.md"))
        XCTAssertEqual(openRecent?.items.last?.title, "Clear Menu")
    }

    func testToolbarInstallsRecentWorkspacesItem() {
        let delegate = RedmarginWindowToolbar()
        let toolbar = NSToolbar(identifier: NSToolbar.Identifier("TestToolbar"))
        let item = delegate.toolbar(
            toolbar,
            itemForItemIdentifier: NSToolbarItem.Identifier("recentWorkspaces"),
            willBeInsertedIntoToolbar: true
        )

        XCTAssertEqual(item?.label, "Recent Workspaces")
        XCTAssertEqual(item?.paletteLabel, "Recent Workspaces")
        XCTAssertEqual(item?.toolTip, "Show Recent Workspaces (⇧⌘1)")
        XCTAssertEqual(item?.action, #selector(AppDelegate.showRecentWorkspaces(_:)))
    }
}

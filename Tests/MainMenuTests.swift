import AppKit
import SwiftUI
import XCTest
@testable import Redmargin
@testable import RedmarginCore

@MainActor
final class MainMenuTests: XCTestCase {
    private var savedRecentWorkspaces: Data?
    private var savedRecentWorkspacesFrame: String?
    private var savedCommandPaletteFrame: String?
    private var savedCommandPaletteAutosaveFrame: String?
    private var savedRestoreProgressFrame: String?
    private var savedRestoreProgressAutosaveFrame: String?

    override func setUp() {
        super.setUp()
        savedRecentWorkspaces = UserDefaults.standard.data(forKey: RecentWorkspaceStore.defaultsKey)
        UserDefaults.standard.removeObject(forKey: RecentWorkspaceStore.defaultsKey)
        savedRecentWorkspacesFrame = UserDefaults.standard.string(forKey: RecentWorkspacesWindowController.frameDefaultsKey)
        UserDefaults.standard.removeObject(forKey: RecentWorkspacesWindowController.frameDefaultsKey)
        savedCommandPaletteFrame = UserDefaults.standard.string(forKey: CommandPaletteWindowController.frameDefaultsKey)
        UserDefaults.standard.removeObject(forKey: CommandPaletteWindowController.frameDefaultsKey)
        savedCommandPaletteAutosaveFrame = UserDefaults.standard.string(
            forKey: "NSWindow Frame \(CommandPaletteWindowController.frameAutosaveName)"
        )
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(CommandPaletteWindowController.frameAutosaveName)")
        savedRestoreProgressFrame = UserDefaults.standard.string(forKey: RestoreProgressWindowController.frameDefaultsKey)
        UserDefaults.standard.removeObject(forKey: RestoreProgressWindowController.frameDefaultsKey)
        savedRestoreProgressAutosaveFrame = UserDefaults.standard.string(
            forKey: "NSWindow Frame \(RestoreProgressWindowController.frameAutosaveName)"
        )
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(RestoreProgressWindowController.frameAutosaveName)")
    }

    override func tearDown() {
        if let savedRecentWorkspaces {
            UserDefaults.standard.set(savedRecentWorkspaces, forKey: RecentWorkspaceStore.defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: RecentWorkspaceStore.defaultsKey)
        }
        savedRecentWorkspaces = nil
        if let savedRecentWorkspacesFrame {
            UserDefaults.standard.set(savedRecentWorkspacesFrame, forKey: RecentWorkspacesWindowController.frameDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: RecentWorkspacesWindowController.frameDefaultsKey)
        }
        savedRecentWorkspacesFrame = nil
        if let savedCommandPaletteFrame {
            UserDefaults.standard.set(savedCommandPaletteFrame, forKey: CommandPaletteWindowController.frameDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: CommandPaletteWindowController.frameDefaultsKey)
        }
        savedCommandPaletteFrame = nil
        if let savedCommandPaletteAutosaveFrame {
            UserDefaults.standard.set(
                savedCommandPaletteAutosaveFrame,
                forKey: "NSWindow Frame \(CommandPaletteWindowController.frameAutosaveName)"
            )
        } else {
            UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(CommandPaletteWindowController.frameAutosaveName)")
        }
        savedCommandPaletteAutosaveFrame = nil
        if let savedRestoreProgressFrame {
            UserDefaults.standard.set(savedRestoreProgressFrame, forKey: RestoreProgressWindowController.frameDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: RestoreProgressWindowController.frameDefaultsKey)
        }
        savedRestoreProgressFrame = nil
        if let savedRestoreProgressAutosaveFrame {
            UserDefaults.standard.set(
                savedRestoreProgressAutosaveFrame,
                forKey: "NSWindow Frame \(RestoreProgressWindowController.frameAutosaveName)"
            )
        } else {
            UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(RestoreProgressWindowController.frameAutosaveName)")
        }
        savedRestoreProgressAutosaveFrame = nil
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

    func testRecentWorkspacesWindowRestoresSavedFrame() {
        let savedFrame = NSRect(x: 80, y: 90, width: 700, height: 500)
        UserDefaults.standard.set(
            NSStringFromRect(savedFrame),
            forKey: RecentWorkspacesWindowController.frameDefaultsKey
        )

        let restoredWindow = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        RecentWorkspacesWindowController.configureFramePersistence(on: restoredWindow)

        XCTAssertEqual(restoredWindow.frame.width, 700, accuracy: 1)
        XCTAssertEqual(restoredWindow.frame.height, 500, accuracy: 1)
    }

    func testCommandPaletteWindowRestoresSavedFrame() {
        let savedFrame = NSRect(x: 160, y: 170, width: 720, height: 520)
        UserDefaults.standard.set(
            NSStringFromRect(savedFrame),
            forKey: CommandPaletteWindowController.frameDefaultsKey
        )
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)

        CommandPaletteWindowController.configureFramePersistence(on: window)

        XCTAssertEqual(window.frame.origin.x, savedFrame.origin.x, accuracy: 1)
        XCTAssertEqual(window.frame.origin.y, savedFrame.origin.y, accuracy: 1)
        XCTAssertEqual(window.frame.width, savedFrame.width, accuracy: 1)
        XCTAssertEqual(window.frame.height, savedFrame.height, accuracy: 1)
    }

    func testCommandPaletteWindowSavesCurrentFrame() throws {
        let contentRect = NSRect(x: 190, y: 210, width: 760, height: 560)
        let window = NSWindow(contentRect: contentRect, styleMask: [.titled], backing: .buffered, defer: false)
        let savedFrame = window.frame

        CommandPaletteWindowController.saveFrame(of: window)

        let frameString = UserDefaults.standard.string(forKey: CommandPaletteWindowController.frameDefaultsKey)
        let restoredFrame = try XCTUnwrap(frameString.map(NSRectFromString))
        XCTAssertEqual(restoredFrame.origin.x, savedFrame.origin.x, accuracy: 1)
        XCTAssertEqual(restoredFrame.origin.y, savedFrame.origin.y, accuracy: 1)
        XCTAssertEqual(restoredFrame.width, savedFrame.width, accuracy: 1)
        XCTAssertEqual(restoredFrame.height, savedFrame.height, accuracy: 1)
    }

    func testCommandPaletteSavedFrameWinsAfterHostingViewInstall() {
        let savedFrame = NSRect(x: 220, y: 240, width: 780, height: 580)
        UserDefaults.standard.set(
            NSStringFromRect(savedFrame),
            forKey: CommandPaletteWindowController.frameDefaultsKey
        )
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        CommandPaletteWindowController.configureFramePersistence(on: window)

        window.contentViewController = NSHostingController(
            rootView: Text("Command Palette").frame(width: 640, height: 420)
        )
        CommandPaletteWindowController.restoreSavedFrame(on: window)

        XCTAssertEqual(window.frame.origin.x, savedFrame.origin.x, accuracy: 1)
        XCTAssertEqual(window.frame.origin.y, savedFrame.origin.y, accuracy: 1)
        XCTAssertEqual(window.frame.width, savedFrame.width, accuracy: 1)
        XCTAssertEqual(window.frame.height, savedFrame.height, accuracy: 1)
    }

    func testRestoreProgressWindowBalancesActivities() {
        let appDelegate = AppDelegate()

        appDelegate.beginRestoreActivity("Restoring remote windows...")
        XCTAssertEqual(appDelegate.restoreActivityCount, 1)
        XCTAssertNotNil(appDelegate.restoreProgressWindowController)

        appDelegate.beginRestoreActivity("Opening remote windows...")
        XCTAssertEqual(appDelegate.restoreActivityCount, 2)

        appDelegate.endRestoreActivity()
        XCTAssertEqual(appDelegate.restoreActivityCount, 1)
        XCTAssertNotNil(appDelegate.restoreProgressWindowController)

        appDelegate.endRestoreActivity()
        XCTAssertEqual(appDelegate.restoreActivityCount, 0)
        XCTAssertNil(appDelegate.restoreProgressWindowController)
    }

    func testRestoreProgressWindowCentersOnVisibleScreen() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 132),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )

        RestoreProgressWindowController.centerOnVisibleScreen(window, screen: screen)

        XCTAssertEqual(window.frame.midX, screen.visibleFrame.midX, accuracy: 1)
        XCTAssertEqual(window.frame.midY, screen.visibleFrame.midY, accuracy: 1)
    }

    func testRestoreProgressWindowRestoresSavedFrame() {
        let savedFrame = NSRect(x: 120, y: 140, width: 440, height: 132)
        UserDefaults.standard.set(
            NSStringFromRect(savedFrame),
            forKey: RestoreProgressWindowController.frameDefaultsKey
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 132),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )

        RestoreProgressWindowController.configureFramePersistence(on: window)

        XCTAssertEqual(window.frame.origin.x, savedFrame.origin.x, accuracy: 1)
        XCTAssertEqual(window.frame.origin.y, savedFrame.origin.y, accuracy: 1)
    }

    func testRestoreProgressWindowUpdateKeepsCurrentFrame() throws {
        let controller = RestoreProgressWindowController(message: "Restoring remote windows...")
        let movedFrame = NSRect(x: 180, y: 210, width: 440, height: 132)
        controller.window?.setFrame(movedFrame, display: false)

        controller.update(message: "Opening remote windows...")

        let frame = try XCTUnwrap(controller.window?.frame)
        XCTAssertEqual(frame.origin.x, movedFrame.origin.x, accuracy: 1)
        XCTAssertEqual(frame.origin.y, movedFrame.origin.y, accuracy: 1)
    }
}

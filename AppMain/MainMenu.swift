import AppKit
import RedmarginLib

private var recentMenuDelegate: RecentDocumentsMenuDelegate?

func setupMainMenu(target: AppDelegate) {
    let mainMenu = NSMenu()

    // App menu
    let appMenu = NSMenu()
    let appMenuItem = NSMenuItem(title: "Redmargin", action: nil, keyEquivalent: "")
    appMenuItem.submenu = appMenu
    mainMenu.addItem(appMenuItem)

    appMenu.addItem(withTitle: "About Redmargin", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
    appMenu.addItem(NSMenuItem.separator())

    let prefsItem = NSMenuItem(title: "Settings...", action: #selector(AppDelegate.showPreferences(_:)), keyEquivalent: ",")
    prefsItem.target = target
    appMenu.addItem(prefsItem)
    appMenu.addItem(NSMenuItem.separator())

    appMenu.addItem(withTitle: "Quit Redmargin", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

    // File menu
    let fileMenu = NSMenu(title: "File")
    let fileMenuItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
    fileMenuItem.submenu = fileMenu
    mainMenu.addItem(fileMenuItem)

    let openItem = NSMenuItem(title: "Open...", action: #selector(AppDelegate.showOpenPanel), keyEquivalent: "o")
    openItem.target = target
    fileMenu.addItem(openItem)

    let recentMenu = NSMenu(title: "Open Recent")
    let recentMenuItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
    recentMenuItem.submenu = recentMenu
    recentMenuDelegate = RecentDocumentsMenuDelegate(appDelegate: target)
    recentMenu.delegate = recentMenuDelegate
    fileMenu.addItem(recentMenuItem)

    fileMenu.addItem(NSMenuItem.separator())

    let printItem = NSMenuItem(title: "Print...", action: #selector(AppDelegate.printDocument(_:)), keyEquivalent: "p")
    printItem.target = target
    fileMenu.addItem(printItem)

    fileMenu.addItem(NSMenuItem.separator())

    let closeItem = NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    fileMenu.addItem(closeItem)

    // Edit menu
    let editMenu = NSMenu(title: "Edit")
    let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
    editMenuItem.submenu = editMenu
    mainMenu.addItem(editMenuItem)

    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(NSMenuItem.separator())
    editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editMenu.addItem(NSMenuItem.separator())

    let findItem = NSMenuItem(title: "Find...", action: #selector(AppDelegate.showFindBar(_:)), keyEquivalent: "f")
    findItem.target = target
    editMenu.addItem(findItem)

    let findNextItem = NSMenuItem(title: "Find Next", action: #selector(AppDelegate.findNext(_:)), keyEquivalent: "g")
    findNextItem.target = target
    editMenu.addItem(findNextItem)

    let findPrevItem = NSMenuItem(title: "Find Previous", action: #selector(AppDelegate.findPrevious(_:)), keyEquivalent: "G")
    findPrevItem.keyEquivalentModifierMask = [.command, .shift]
    findPrevItem.target = target
    editMenu.addItem(findPrevItem)

    // View menu
    let viewMenu = NSMenu(title: "View")
    let viewMenuItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
    viewMenuItem.submenu = viewMenu
    mainMenu.addItem(viewMenuItem)

    let refreshItem = NSMenuItem(title: "Refresh", action: #selector(AppDelegate.refreshDocument(_:)), keyEquivalent: "r")
    refreshItem.target = target
    viewMenu.addItem(refreshItem)

    let lineNumbersItem = NSMenuItem(title: "Toggle Line Numbers", action: #selector(AppDelegate.toggleLineNumbers(_:)), keyEquivalent: "l")
    lineNumbersItem.target = target
    viewMenu.addItem(lineNumbersItem)

    // Window menu
    let windowMenu = NSMenu(title: "Window")
    let windowMenuItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
    windowMenuItem.submenu = windowMenu
    mainMenu.addItem(windowMenuItem)

    windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
    windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")

    NSApp.windowsMenu = windowMenu

    // Help menu
    let helpMenu = NSMenu(title: "Help")
    let helpMenuItem = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
    helpMenuItem.submenu = helpMenu
    mainMenu.addItem(helpMenuItem)

    NSApp.helpMenu = helpMenu

    NSApp.mainMenu = mainMenu
}

// MARK: - Recent Documents Menu Delegate

final class RecentDocumentsMenuDelegate: NSObject, NSMenuDelegate {
    private weak var appDelegate: AppDelegate?

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        super.init()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        guard let appDelegate = appDelegate else { return }

        for url in appDelegate.recentDocuments {
            let item = NSMenuItem(title: url.displayPath, action: #selector(openRecentDocument(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            menu.addItem(item)
        }

        if !appDelegate.recentDocuments.isEmpty {
            menu.addItem(NSMenuItem.separator())
            let clearItem = NSMenuItem(title: "Clear Menu", action: #selector(clearRecentDocuments(_:)), keyEquivalent: "")
            clearItem.target = self
            menu.addItem(clearItem)
        }
    }

    @objc private func openRecentDocument(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        appDelegate?.openDocument(url)
    }

    @objc private func clearRecentDocuments(_ sender: NSMenuItem) {
        appDelegate?.clearRecentDocuments()
    }
}

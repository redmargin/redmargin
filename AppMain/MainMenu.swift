import AppKit
import SwiftUI
import RedmarginLib
import RedmarginCore

private var recentMenuDelegate: RecentDocumentsMenuDelegate?

@MainActor
func setupMainMenu(target: AppDelegate) {
    let mainMenu = NSMenu()

    mainMenu.addItem(createAppMenu(target: target))
    mainMenu.addItem(createFileMenu(target: target))
    mainMenu.addItem(createEditMenu(target: target))
    mainMenu.addItem(createViewMenu(target: target))
    mainMenu.addItem(createWindowMenu())
    mainMenu.addItem(createHelpMenu())

    NSApp.mainMenu = mainMenu
}

// MARK: - Menu Builders

private func createAppMenu(target: AppDelegate) -> NSMenuItem {
    let appMenu = NSMenu()
    let appMenuItem = NSMenuItem(title: "Redmargin", action: nil, keyEquivalent: "")
    appMenuItem.submenu = appMenu

    let aboutItem = NSMenuItem(
        title: "About Redmargin", action: #selector(AppDelegate.showAbout(_:)), keyEquivalent: "")
    aboutItem.target = target
    appMenu.addItem(aboutItem)
    appMenu.addItem(NSMenuItem.separator())

    let prefsItem = NSMenuItem(
        title: "Settings...", action: #selector(AppDelegate.showPreferences(_:)), keyEquivalent: ",")
    prefsItem.target = target
    appMenu.addItem(prefsItem)
    appMenu.addItem(NSMenuItem.separator())

    appMenu.addItem(withTitle: "Quit Redmargin", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

    return appMenuItem
}

private func createFileMenu(target: AppDelegate) -> NSMenuItem {
    let fileMenu = NSMenu(title: "File")
    let fileMenuItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
    fileMenuItem.submenu = fileMenu

    let openItem = NSMenuItem(title: "Open...", action: #selector(AppDelegate.showOpenPanel), keyEquivalent: "o")
    openItem.target = target
    fileMenu.addItem(openItem)

    let openRemoteItem = NSMenuItem(
        title: "Open Remote...", action: #selector(AppDelegate.showOpenRemoteSheet), keyEquivalent: "O")
    openRemoteItem.keyEquivalentModifierMask = [.command, .shift]
    openRemoteItem.target = target
    fileMenu.addItem(openRemoteItem)

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

    let exportItem = NSMenuItem(
        title: "Export as PDF", action: #selector(AppDelegate.exportDocument(_:)), keyEquivalent: "e")
    exportItem.target = target
    fileMenu.addItem(exportItem)

    fileMenu.addItem(NSMenuItem.separator())

    let closeItem = NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    fileMenu.addItem(closeItem)

    return fileMenuItem
}

private func createEditMenu(target: AppDelegate) -> NSMenuItem {
    let editMenu = NSMenu(title: "Edit")
    let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
    editMenuItem.submenu = editMenu

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

    let findPrevItem = NSMenuItem(
        title: "Find Previous", action: #selector(AppDelegate.findPrevious(_:)), keyEquivalent: "G")
    findPrevItem.keyEquivalentModifierMask = [.command, .shift]
    findPrevItem.target = target
    editMenu.addItem(findPrevItem)

    return editMenuItem
}

private var viewMenuDelegate: ViewMenuDelegate?

private func createViewMenu(target: AppDelegate) -> NSMenuItem {
    let viewMenu = NSMenu(title: "View")
    let viewMenuItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
    viewMenuItem.submenu = viewMenu
    viewMenuDelegate = ViewMenuDelegate(appDelegate: target)
    viewMenu.delegate = viewMenuDelegate

    let refreshItem = NSMenuItem(
        title: "Refresh", action: #selector(AppDelegate.refreshDocument(_:)), keyEquivalent: "r")
    refreshItem.target = target
    viewMenu.addItem(refreshItem)

    viewMenu.addItem(NSMenuItem.separator())

    let gutterItem = NSMenuItem(
        title: "Show Gutter",
        action: #selector(AppDelegate.toggleGutter(_:)),
        keyEquivalent: "g")
    gutterItem.keyEquivalentModifierMask = [.command, .option]
    gutterItem.target = target
    gutterItem.tag = ViewMenuTag.gutter.rawValue
    viewMenu.addItem(gutterItem)

    let lineNumbersItem = NSMenuItem(
        title: "Show Line Numbers",
        action: #selector(AppDelegate.toggleLineNumbers(_:)),
        keyEquivalent: "l")
    lineNumbersItem.target = target
    lineNumbersItem.tag = ViewMenuTag.lineNumbers.rawValue
    viewMenu.addItem(lineNumbersItem)

    let gitIndicatorsItem = NSMenuItem(
        title: "Show Git Indicators",
        action: #selector(AppDelegate.toggleGitIndicators(_:)),
        keyEquivalent: "i")
    gitIndicatorsItem.keyEquivalentModifierMask = [.command, .shift]
    gitIndicatorsItem.target = target
    gitIndicatorsItem.tag = ViewMenuTag.gitIndicators.rawValue
    viewMenu.addItem(gitIndicatorsItem)

    return viewMenuItem
}

private enum ViewMenuTag: Int {
    case gutter = 100
    case lineNumbers = 101
    case gitIndicators = 102
}

final class ViewMenuDelegate: NSObject, NSMenuDelegate {
    private weak var appDelegate: AppDelegate?

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        super.init()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let appDelegate = appDelegate else { return }
        let prefs = PreferencesManager.shared

        // Determine state based on current document, falling back to preferences
        var gutterVisible = prefs.showGutter
        var lineNumbersVisible = prefs.showLineNumbers
        var gitIndicatorsVisible = prefs.showGitIndicators

        if let window = NSApp.keyWindow {
            if let hostingVC = window.contentViewController as? NSHostingController<DocumentWindowContent> {
                let url = hostingVC.rootView.fileURL
                gutterVisible = appDelegate.loadGutterVisible(for: url) ?? prefs.showGutter
                lineNumbersVisible = appDelegate.loadLineNumbersVisible(for: url)
                gitIndicatorsVisible = appDelegate.loadGitIndicatorsVisible(for: url) ?? prefs.showGitIndicators
            } else if let hostingVC = window.contentViewController
                        as? NSHostingController<RemoteDocumentWindowContent> {
                let location = hostingVC.rootView.location
                gutterVisible = appDelegate.loadGutterVisible(for: location) ?? prefs.showGutter
                lineNumbersVisible = appDelegate.loadLineNumbersVisible(for: location)
                gitIndicatorsVisible = appDelegate.loadGitIndicatorsVisible(for: location) ?? prefs.showGitIndicators
            }
        }

        for item in menu.items {
            switch item.tag {
            case ViewMenuTag.gutter.rawValue:
                item.title = gutterVisible ? "Hide Gutter" : "Show Gutter"
            case ViewMenuTag.lineNumbers.rawValue:
                item.title = lineNumbersVisible ? "Hide Line Numbers" : "Show Line Numbers"
            case ViewMenuTag.gitIndicators.rawValue:
                item.title = gitIndicatorsVisible ? "Hide Git Indicators" : "Show Git Indicators"
            default:
                break
            }
        }
    }
}

@MainActor
private var windowMenuDelegate: WindowMenuDelegate?

@MainActor
private func createWindowMenu() -> NSMenuItem {
    let windowMenu = NSMenu(title: "Window")
    let windowMenuItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
    windowMenuItem.submenu = windowMenu

    // Remove "Enter Full Screen" that macOS adds automatically
    windowMenuDelegate = WindowMenuDelegate()
    windowMenu.delegate = windowMenuDelegate

    windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
    windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")

    NSApp.windowsMenu = windowMenu

    return windowMenuItem
}

/// Delegate that removes the "Enter Full Screen" item macOS automatically adds
@MainActor
final class WindowMenuDelegate: NSObject, NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items where item.action == #selector(NSWindow.toggleFullScreen(_:)) {
            menu.removeItem(item)
        }
    }
}

private func createHelpMenu() -> NSMenuItem {
    let helpMenu = NSMenu(title: "Help")
    let helpMenuItem = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
    helpMenuItem.submenu = helpMenu

    NSApp.helpMenu = helpMenu

    return helpMenuItem
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
            let item = NSMenuItem(
                title: url.displayPath, action: #selector(openRecentDocument(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            menu.addItem(item)
        }

        if !appDelegate.recentRemoteLocations.isEmpty {
            if !appDelegate.recentDocuments.isEmpty {
                menu.addItem(NSMenuItem.separator())
            }

            for location in appDelegate.recentRemoteLocations {
                let item = NSMenuItem(
                    title: location.displayString,
                    action: #selector(openRecentRemoteLocation(_:)),
                    keyEquivalent: "")
                item.target = self
                item.representedObject = location
                menu.addItem(item)
            }
        }

        let hasItems = !appDelegate.recentDocuments.isEmpty || !appDelegate.recentRemoteLocations.isEmpty
        if hasItems {
            menu.addItem(NSMenuItem.separator())
            let clearItem = NSMenuItem(
                title: "Clear Menu", action: #selector(clearRecentDocuments(_:)), keyEquivalent: "")
            clearItem.target = self
            menu.addItem(clearItem)
        }
    }

    @objc private func openRecentDocument(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL,
              let appDelegate = appDelegate else { return }

        if !FileManager.default.fileExists(atPath: url.path) {
            appDelegate.recentDocuments.removeAll { $0 == url }
            UserDefaults.standard.set(
                appDelegate.recentDocuments.map { $0.path },
                forKey: "RedMargin.RecentDocumentURLs"
            )

            let alert = NSAlert()
            alert.messageText = "File Not Found"
            alert.informativeText = """
                The file no longer exists at:
                \(url.path)

                It has been removed from Recent Documents.
                """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        appDelegate.openDocument(url)
    }

    @objc private func openRecentRemoteLocation(_ sender: NSMenuItem) {
        guard let location = sender.representedObject as? RemoteLocation else { return }
        appDelegate?.openRecentRemoteLocation(location)
    }

    @objc private func clearRecentDocuments(_ sender: NSMenuItem) {
        appDelegate?.clearRecentDocuments()
        appDelegate?.clearRecentRemoteLocations()
    }
}

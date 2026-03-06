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

    let sidebarItem = NSMenuItem(
        title: "Show Sidebar",
        action: #selector(AppDelegate.toggleSidebar(_:)),
        keyEquivalent: "1")
    sidebarItem.target = target
    sidebarItem.tag = ViewMenuTag.sidebar
    sidebarItem.image = menuIcon("sidebar.left")
    viewMenu.addItem(sidebarItem)

    viewMenu.addItem(NSMenuItem.separator())

    let refreshItem = NSMenuItem(
        title: "Refresh", action: #selector(AppDelegate.refreshDocument(_:)), keyEquivalent: "r")
    refreshItem.target = target
    refreshItem.image = menuIcon("arrow.clockwise")
    viewMenu.addItem(refreshItem)

    viewMenu.addItem(NSMenuItem.separator())

    let gutterItem = NSMenuItem(
        title: "Show Gutter",
        action: #selector(AppDelegate.toggleGutter(_:)),
        keyEquivalent: "g")
    gutterItem.keyEquivalentModifierMask = [.command, .option]
    gutterItem.target = target
    gutterItem.tag = ViewMenuTag.gutter
    gutterItem.image = menuIcon("rectangle.lefthalf.inset.filled")
    viewMenu.addItem(gutterItem)

    let lineNumbersItem = NSMenuItem(
        title: "Show Line Numbers",
        action: #selector(AppDelegate.toggleLineNumbers(_:)),
        keyEquivalent: "l")
    lineNumbersItem.target = target
    lineNumbersItem.tag = ViewMenuTag.lineNumbers
    lineNumbersItem.image = menuIcon("list.number")
    viewMenu.addItem(lineNumbersItem)

    let gitIndicatorsItem = NSMenuItem(
        title: "Show Git Indicators",
        action: #selector(AppDelegate.toggleGitIndicators(_:)),
        keyEquivalent: "i")
    gitIndicatorsItem.keyEquivalentModifierMask = [.command, .shift]
    gitIndicatorsItem.target = target
    gitIndicatorsItem.tag = ViewMenuTag.gitIndicators
    gitIndicatorsItem.image = menuIcon("arrow.triangle.branch")
    viewMenu.addItem(gitIndicatorsItem)

    viewMenu.addItem(NSMenuItem.separator())

    // Text Width submenu
    let textWidthMenu = NSMenu(title: "Text Width")
    for width in TextWidth.allCases {
        let item = NSMenuItem(
            title: width.rawValue.capitalized,
            action: #selector(AppDelegate.setTextWidth(_:)),
            keyEquivalent: "")
        item.target = target
        item.representedObject = width.rawValue
        item.tag = ViewMenuTag.textWidthBase + TextWidth.allCases.firstIndex(of: width)!
        textWidthMenu.addItem(item)
    }
    let textWidthItem = NSMenuItem(title: "Text Width", action: nil, keyEquivalent: "")
    textWidthItem.submenu = textWidthMenu
    textWidthItem.image = menuIcon("text.alignleft")
    viewMenu.addItem(textWidthItem)

    // Block Width submenu (code blocks, tables, images)
    let contentWidthMenu = NSMenu(title: "Block Width")
    for width in ContentWidth.allCases {
        let item = NSMenuItem(
            title: width.rawValue.capitalized,
            action: #selector(AppDelegate.setContentWidth(_:)),
            keyEquivalent: "")
        item.target = target
        item.representedObject = width.rawValue
        item.tag = ViewMenuTag.contentWidthBase + ContentWidth.allCases.firstIndex(of: width)!
        contentWidthMenu.addItem(item)
    }
    let contentWidthItem = NSMenuItem(title: "Block Width", action: nil, keyEquivalent: "")
    contentWidthItem.submenu = contentWidthMenu
    contentWidthItem.image = menuIcon("rectangle.arrowtriangle.2.outward")
    viewMenu.addItem(contentWidthItem)

    return viewMenuItem
}

private func menuIcon(_ name: String) -> NSImage? {
    let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
    image?.size = NSSize(width: 16, height: 16)
    return image
}

private enum ViewMenuTag {
    static let sidebar = 99
    static let gutter = 100
    static let lineNumbers = 101
    static let gitIndicators = 102
    static let textWidthBase = 200
    static let contentWidthBase = 210
}

final class ViewMenuDelegate: NSObject, NSMenuDelegate {
    private weak var appDelegate: AppDelegate?

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        super.init()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard appDelegate != nil else { return }
        let prefs = PreferencesManager.shared

        // Determine state based on current document, falling back to preferences
        var sidebarVisible = false
        var gutterVisible = prefs.showGutter
        var lineNumbersVisible = prefs.showLineNumbers
        var gitIndicatorsVisible = prefs.showGitIndicators
        var currentTextWidth = prefs.textWidth.rawValue
        var currentContentWidth = prefs.contentWidth.rawValue

        let settings = DocumentSettingsStorage.shared
        if let window = NSApp.keyWindow {
            if let hostingVC = window.contentViewController as? NSHostingController<DocumentWindowContent> {
                let url = hostingVC.rootView.fileURL
                sidebarVisible = settings.loadSidebarVisible(for: url) ?? false
                gutterVisible = settings.loadGutterVisible(for: url) ?? prefs.showGutter
                lineNumbersVisible = settings.loadLineNumbersVisible(for: url)
                gitIndicatorsVisible = settings.loadGitIndicatorsVisible(for: url) ?? prefs.showGitIndicators
                currentTextWidth = settings.loadTextWidth(for: url) ?? prefs.textWidth.rawValue
                currentContentWidth = settings.loadContentWidth(for: url) ?? prefs.contentWidth.rawValue
            } else if let hostingVC = window.contentViewController
                        as? NSHostingController<FolderWindowContent> {
                let url = hostingVC.rootView.folderURL
                sidebarVisible = settings.loadSidebarVisible(for: url) ?? true
                gutterVisible = settings.loadGutterVisible(for: url) ?? prefs.showGutter
                lineNumbersVisible = settings.loadLineNumbersVisible(for: url)
                gitIndicatorsVisible = settings.loadGitIndicatorsVisible(for: url) ?? prefs.showGitIndicators
                currentTextWidth = settings.loadTextWidth(for: url) ?? prefs.textWidth.rawValue
                currentContentWidth = settings.loadContentWidth(for: url) ?? prefs.contentWidth.rawValue
            } else if let hostingVC = window.contentViewController
                        as? NSHostingController<RemoteDocumentWindowContent> {
                let location = hostingVC.rootView.location
                sidebarVisible = settings.loadSidebarVisible(for: location) ?? false
                gutterVisible = settings.loadGutterVisible(for: location) ?? prefs.showGutter
                lineNumbersVisible = settings.loadLineNumbersVisible(for: location)
                gitIndicatorsVisible = settings.loadGitIndicatorsVisible(for: location) ?? prefs.showGitIndicators
                currentTextWidth = settings.loadTextWidth(for: location) ?? prefs.textWidth.rawValue
                currentContentWidth = settings.loadContentWidth(for: location) ?? prefs.contentWidth.rawValue
            }
        }

        for item in menu.items {
            switch item.tag {
            case ViewMenuTag.sidebar:
                item.title = sidebarVisible ? "Hide Sidebar" : "Show Sidebar"
            case ViewMenuTag.gutter:
                item.title = gutterVisible ? "Hide Gutter" : "Show Gutter"
            case ViewMenuTag.lineNumbers:
                item.title = lineNumbersVisible ? "Hide Line Numbers" : "Show Line Numbers"
            case ViewMenuTag.gitIndicators:
                item.title = gitIndicatorsVisible ? "Hide Git Indicators" : "Show Git Indicators"
            default:
                break
            }

            // Update checkmarks on width submenu items
            if let submenu = item.submenu {
                for subItem in submenu.items {
                    if subItem.tag >= ViewMenuTag.textWidthBase
                        && subItem.tag < ViewMenuTag.textWidthBase + 10 {
                        subItem.state = (subItem.representedObject as? String) == currentTextWidth ? .on : .off
                    } else if subItem.tag >= ViewMenuTag.contentWidthBase
                                && subItem.tag < ViewMenuTag.contentWidthBase + 10 {
                        subItem.state = (subItem.representedObject as? String) == currentContentWidth ? .on : .off
                    }
                }
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

        // Partition local recents into files and folders
        var recentFiles: [URL] = []
        var recentFolders: [URL] = []
        for url in appDelegate.recentDocuments {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                recentFolders.append(url)
            } else {
                recentFiles.append(url)
            }
        }

        let hasFiles = !recentFiles.isEmpty
        let hasRemote = !appDelegate.recentRemoteLocations.isEmpty
        let hasFolders = !recentFolders.isEmpty

        // Documents section
        if hasFiles {
            menu.addItem(sectionHeader("Documents"))
            for url in recentFiles {
                let item = NSMenuItem(
                    title: url.displayPath, action: #selector(openRecentDocument(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = url
                item.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: "Document")
                item.image?.size = NSSize(width: 16, height: 16)
                menu.addItem(item)
            }
        }

        // Remote Documents section
        if hasRemote {
            menu.addItem(sectionHeader("Remote Documents"))
            for location in appDelegate.recentRemoteLocations {
                let item = NSMenuItem(
                    title: location.displayString,
                    action: #selector(openRecentRemoteLocation(_:)),
                    keyEquivalent: "")
                item.target = self
                item.representedObject = location
                item.image = NSImage(systemSymbolName: "network", accessibilityDescription: "Remote")
                item.image?.size = NSSize(width: 14, height: 14)
                menu.addItem(item)
            }
        }

        // Folders section
        if hasFolders {
            menu.addItem(sectionHeader("Folders"))
            for url in recentFolders {
                let item = NSMenuItem(
                    title: url.displayPath, action: #selector(openRecentDocument(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = url
                item.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: "Folder")
                item.image?.size = NSSize(width: 16, height: 16)
                menu.addItem(item)
            }
        }

        if hasFiles || hasRemote || hasFolders {
            menu.addItem(NSMenuItem.separator())
            let clearItem = NSMenuItem(
                title: "Clear Menu", action: #selector(clearRecentDocuments(_:)), keyEquivalent: "")
            clearItem.target = self
            menu.addItem(clearItem)
        }
    }

    private func sectionHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem.sectionHeader(title: title)
        return item
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

        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if isDir.boolValue {
            appDelegate.openFolder(url)
        } else {
            appDelegate.openDocument(url)
        }
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

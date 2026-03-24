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

    addSidebarItems(to: viewMenu, target: target)
    viewMenu.addItem(NSMenuItem.separator())
    addRefreshItem(to: viewMenu, target: target)
    viewMenu.addItem(NSMenuItem.separator())
    addDisplayItems(to: viewMenu, target: target)
    viewMenu.addItem(NSMenuItem.separator())
    addWidthItems(to: viewMenu, target: target)
    return viewMenuItem
}
private func addSidebarItems(to menu: NSMenu, target: AppDelegate) {
    menu.addItem(makeViewActionItem(
        title: "Show Sidebar",
        action: #selector(AppDelegate.toggleSidebar(_:)),
        keyEquivalent: "1",
        target: target,
        tag: ViewMenuTag.sidebar,
        imageName: "sidebar.left"
    ))
    menu.addItem(makeViewActionItem(
        title: "Show Hidden Files",
        action: #selector(AppDelegate.toggleHiddenFiles(_:)),
        keyEquivalent: ".",
        target: target,
        tag: ViewMenuTag.hiddenFiles,
        imageName: "eye",
        modifierMask: [.command, .shift]
    ))
}
private func addRefreshItem(to menu: NSMenu, target: AppDelegate) {
    menu.addItem(makeViewActionItem(
        title: "Refresh",
        action: #selector(AppDelegate.refreshDocument(_:)),
        keyEquivalent: "r",
        target: target,
        imageName: "arrow.clockwise"
    ))
}
private func addDisplayItems(to menu: NSMenu, target: AppDelegate) {
    menu.addItem(makeViewActionItem(
        title: "Show Gutter",
        action: #selector(AppDelegate.toggleGutter(_:)),
        keyEquivalent: "g",
        target: target,
        tag: ViewMenuTag.gutter,
        imageName: "rectangle.lefthalf.inset.filled",
        modifierMask: [.command, .option]
    ))
    menu.addItem(makeViewActionItem(
        title: "Show Line Numbers",
        action: #selector(AppDelegate.toggleLineNumbers(_:)),
        keyEquivalent: "l",
        target: target,
        tag: ViewMenuTag.lineNumbers,
        imageName: "list.number"
    ))
    menu.addItem(makeViewActionItem(
        title: "Show Git Indicators",
        action: #selector(AppDelegate.toggleGitIndicators(_:)),
        keyEquivalent: "i",
        target: target,
        tag: ViewMenuTag.gitIndicators,
        imageName: "arrow.triangle.branch",
        modifierMask: [.command, .shift]
    ))
}
private func addWidthItems(to menu: NSMenu, target: AppDelegate) {
    menu.addItem(makeWidthMenuItem(
        definition: WidthMenuDefinition(
            title: "Text Width",
            imageName: "text.alignleft",
            values: TextWidth.allCases.map(\.rawValue),
            action: #selector(AppDelegate.setTextWidth(_:)),
            tagBase: ViewMenuTag.textWidthBase
        ),
        target: target
    ))
    menu.addItem(makeWidthMenuItem(
        definition: WidthMenuDefinition(
            title: "Block Width",
            imageName: "rectangle.arrowtriangle.2.outward",
            values: ContentWidth.allCases.map(\.rawValue),
            action: #selector(AppDelegate.setContentWidth(_:)),
            tagBase: ViewMenuTag.contentWidthBase
        ),
        target: target
    ))
}
private func makeViewActionItem(
    title: String,
    action: Selector,
    keyEquivalent: String,
    target: AppDelegate,
    tag: Int? = nil,
    imageName: String? = nil,
    modifierMask: NSEvent.ModifierFlags = [.command]
) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
    item.target = target
    item.keyEquivalentModifierMask = modifierMask
    item.tag = tag ?? 0
    if let imageName {
        item.image = menuIcon(imageName)
    }
    return item
}
private struct WidthMenuDefinition {
    let title: String
    let imageName: String
    let values: [String]
    let action: Selector
    let tagBase: Int
}
private func makeWidthMenuItem(definition: WidthMenuDefinition, target: AppDelegate) -> NSMenuItem {
    let submenu = NSMenu(title: definition.title)
    for (index, value) in definition.values.enumerated() {
        let item = NSMenuItem(title: value.capitalized, action: definition.action, keyEquivalent: "")
        item.target = target
        item.representedObject = value
        item.tag = definition.tagBase + index
        submenu.addItem(item)
    }

    let item = NSMenuItem(title: definition.title, action: nil, keyEquivalent: "")
    item.submenu = submenu
    item.image = menuIcon(definition.imageName)
    return item
}
private func menuIcon(_ name: String) -> NSImage? {
    let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
    image?.size = NSSize(width: 16, height: 16)
    return image
}

private enum ViewMenuTag {
    static let sidebar = 99
    static let hiddenFiles = 98
    static let gutter = 100
    static let lineNumbers = 101
    static let gitIndicators = 102
    static let textWidthBase = 200
    static let contentWidthBase = 210
}

private struct ViewMenuState {
    let sidebarVisible: Bool
    let hiddenFilesVisible: Bool
    let gutterVisible: Bool
    let lineNumbersVisible: Bool
    let gitIndicatorsVisible: Bool
    let currentTextWidth: String
    let currentContentWidth: String

    static func defaults(from prefs: PreferencesManager) -> ViewMenuState {
        ViewMenuState(
            sidebarVisible: false,
            hiddenFilesVisible: prefs.showHiddenFiles,
            gutterVisible: prefs.showGutter,
            lineNumbersVisible: prefs.showLineNumbers,
            gitIndicatorsVisible: prefs.showGitIndicators,
            currentTextWidth: prefs.textWidth.rawValue,
            currentContentWidth: prefs.contentWidth.rawValue
        )
    }
}

final class ViewMenuDelegate: NSObject, NSMenuDelegate {
    private weak var appDelegate: AppDelegate?

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        super.init()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard appDelegate != nil else { return }
        let state = resolveViewMenuState()

        for item in menu.items {
            updateTitle(for: item, state: state)
            updateSubmenuStates(for: item, state: state)
        }
    }

    private func resolveViewMenuState() -> ViewMenuState {
        let prefs = PreferencesManager.shared
        let settings = DocumentSettingsStorage.shared

        guard let window = NSApp.keyWindow else {
            return .defaults(from: prefs)
        }
        if let hostingVC = window.contentViewController as? NSHostingController<DocumentWindowContent> {
            return localState(
                for: hostingVC.rootView.fileURL,
                defaultSidebarVisible: false,
                prefs: prefs,
                settings: settings
            )
        }
        if let hostingVC = window.contentViewController as? NSHostingController<FolderWindowContent> {
            return localState(
                for: hostingVC.rootView.folderURL,
                defaultSidebarVisible: true,
                prefs: prefs,
                settings: settings
            )
        }
        if let hostingVC = window.contentViewController as? NSHostingController<RemoteDocumentWindowContent> {
            return remoteState(
                for: hostingVC.rootView.location,
                defaultSidebarVisible: false,
                prefs: prefs,
                settings: settings
            )
        }
        return .defaults(from: prefs)
    }

    private func localState(
        for url: URL,
        defaultSidebarVisible: Bool,
        prefs: PreferencesManager,
        settings: DocumentSettingsStorage
    ) -> ViewMenuState {
        ViewMenuState(
            sidebarVisible: settings.loadSidebarVisible(for: url) ?? defaultSidebarVisible,
            hiddenFilesVisible: settings.loadHiddenFilesVisible(for: url) ?? prefs.showHiddenFiles,
            gutterVisible: settings.loadGutterVisible(for: url) ?? prefs.showGutter,
            lineNumbersVisible: settings.loadLineNumbersVisible(for: url),
            gitIndicatorsVisible: settings.loadGitIndicatorsVisible(for: url) ?? prefs.showGitIndicators,
            currentTextWidth: settings.loadTextWidth(for: url) ?? prefs.textWidth.rawValue,
            currentContentWidth: settings.loadContentWidth(for: url) ?? prefs.contentWidth.rawValue
        )
    }

    private func remoteState(
        for location: RemoteLocation,
        defaultSidebarVisible: Bool,
        prefs: PreferencesManager,
        settings: DocumentSettingsStorage
    ) -> ViewMenuState {
        ViewMenuState(
            sidebarVisible: settings.loadSidebarVisible(for: location) ?? defaultSidebarVisible,
            hiddenFilesVisible: settings.loadHiddenFilesVisible(for: location) ?? prefs.showHiddenFiles,
            gutterVisible: settings.loadGutterVisible(for: location) ?? prefs.showGutter,
            lineNumbersVisible: settings.loadLineNumbersVisible(for: location),
            gitIndicatorsVisible: settings.loadGitIndicatorsVisible(for: location) ?? prefs.showGitIndicators,
            currentTextWidth: settings.loadTextWidth(for: location) ?? prefs.textWidth.rawValue,
            currentContentWidth: settings.loadContentWidth(for: location) ?? prefs.contentWidth.rawValue
        )
    }

    private func updateTitle(for item: NSMenuItem, state: ViewMenuState) {
        switch item.tag {
        case ViewMenuTag.sidebar:
            item.title = state.sidebarVisible ? "Hide Sidebar" : "Show Sidebar"
        case ViewMenuTag.hiddenFiles:
            item.title = state.hiddenFilesVisible ? "Hide Hidden Files" : "Show Hidden Files"
        case ViewMenuTag.gutter:
            item.title = state.gutterVisible ? "Hide Gutter" : "Show Gutter"
        case ViewMenuTag.lineNumbers:
            item.title = state.lineNumbersVisible ? "Hide Line Numbers" : "Show Line Numbers"
        case ViewMenuTag.gitIndicators:
            item.title = state.gitIndicatorsVisible ? "Hide Git Indicators" : "Show Git Indicators"
        default:
            break
        }
    }

    private func updateSubmenuStates(for item: NSMenuItem, state: ViewMenuState) {
        guard let submenu = item.submenu else { return }

        for subItem in submenu.items {
            if subItem.tag >= ViewMenuTag.textWidthBase && subItem.tag < ViewMenuTag.textWidthBase + 10 {
                subItem.state = (subItem.representedObject as? String) == state.currentTextWidth ? .on : .off
            } else if subItem.tag >= ViewMenuTag.contentWidthBase
                        && subItem.tag < ViewMenuTag.contentWidthBase + 10 {
                subItem.state = (subItem.representedObject as? String) == state.currentContentWidth ? .on : .off
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

        let remoteFiles = appDelegate.recentRemoteLocations.filter { !$0.path.hasSuffix("/") }
        let remoteFolders = appDelegate.recentRemoteLocations.filter { $0.path.hasSuffix("/") }

        addDocumentsSection(menu, files: recentFiles)
        addRemoteDocumentsSection(menu, locations: remoteFiles)
        addFoldersSection(menu, localFolders: recentFolders, remoteFolders: remoteFolders)

        let hasAny = !recentFiles.isEmpty || !remoteFiles.isEmpty
            || !remoteFolders.isEmpty || !recentFolders.isEmpty
        if hasAny {
            menu.addItem(NSMenuItem.separator())
            let clearItem = NSMenuItem(
                title: "Clear Menu", action: #selector(clearRecentDocuments(_:)), keyEquivalent: "")
            clearItem.target = self
            menu.addItem(clearItem)
        }
    }

    private func addDocumentsSection(_ menu: NSMenu, files: [URL]) {
        guard !files.isEmpty else { return }
        menu.addItem(sectionHeader("Documents"))
        for url in files {
            let item = NSMenuItem(
                title: url.displayPath, action: #selector(openRecentDocument(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            item.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: "Document")
            item.image?.size = NSSize(width: 16, height: 16)
            menu.addItem(item)
        }
    }

    private func addRemoteDocumentsSection(_ menu: NSMenu, locations: [RemoteLocation]) {
        guard !locations.isEmpty else { return }
        menu.addItem(sectionHeader("Remote Documents"))
        for location in locations {
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

    private func addFoldersSection(
        _ menu: NSMenu, localFolders: [URL], remoteFolders: [RemoteLocation]
    ) {
        guard !localFolders.isEmpty || !remoteFolders.isEmpty else { return }
        menu.addItem(sectionHeader("Folders"))
        for url in localFolders {
            let item = NSMenuItem(
                title: url.displayPath, action: #selector(openRecentDocument(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            item.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: "Folder")
            item.image?.size = NSSize(width: 16, height: 16)
            menu.addItem(item)
        }
        for location in remoteFolders {
            let item = NSMenuItem(
                title: location.displayString,
                action: #selector(openRecentRemoteLocation(_:)),
                keyEquivalent: "")
            item.target = self
            item.representedObject = location
            item.image = NSImage(
                systemSymbolName: "folder.fill.badge.gearshape",
                accessibilityDescription: "Remote Folder")
            item.image?.size = NSSize(width: 16, height: 16)
            menu.addItem(item)
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

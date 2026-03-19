import AppKit
import SwiftUI
import UniformTypeIdentifiers
import RedmarginLib
import RedmarginCore

// Notification.Name and URL extensions are in AppDelegateExtensions.swift

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, ObservableObject {
    private var documentWindows: [URL: NSWindow] = [:]
    var remoteDocumentWindows: [RemoteLocation: NSWindow] = [:]
    var folderWindows: [URL: NSWindow] = [:]
    /// Tracks which file is selected in each folder window (folder URL -> file URL)
    var folderSelectedFiles: [URL: URL] = [:]
    private var launchedWithFiles = false
    private var launchURLs: [URL] = []

    // Cache UTType to avoid repeated LaunchServices lookups
    private static let markdownType = UTType(filenameExtension: "md")!

    // Reuse panel to avoid slow NSOpenPanel initialization
    private lazy var openPanel: NSOpenPanel = {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.markdownType, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.styleMask.insert(.resizable)
        return panel
    }()

    private let savedURLsKey = "RedMargin.OpenDocumentURLs"
    private let recentURLsKey = "RedMargin.RecentDocumentURLs"
    let recentRemoteKey = "RedMargin.RecentRemoteConnections"
    let recentRemoteLocationsKey = "RedMargin.RecentRemoteLocations"
    let openRemoteLocationsKey = "RedMargin.OpenRemoteLocations"
    private let savedFolderURLsKey = "RedMargin.OpenFolderURLs"
    private let folderSelectedFilesKey = "RedMargin.FolderSelectedFiles"
    private let windowOrderKey = "RedMargin.WindowOrder"
    private let frontmostWindowKey = "RedMargin.FrontmostWindow"
    let maxRecentDocuments = 20
    let settings = DocumentSettingsStorage.shared

    @Published var recentDocuments: [URL] = []
    @Published var recentRemoteServers: [String] = []
    @Published var recentRemoteLocations: [RemoteLocation] = []

    override init() {
        super.init()
        recentDocuments = loadRecentDocuments()
        recentRemoteServers = loadRecentRemoteServers()
        recentRemoteLocations = loadRecentRemoteLocations()
    }

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu(target: self)
        BookmarkManager.shared.cleanupStaleBookmarks()
        _ = openPanel  // Pre-initialize to avoid delay on first open

        // Reconnect SSH connections after system wakes from sleep
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSystemWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        let savedURLs = restoreSavedURLs()
        let savedRemoteLocations = restoreOpenRemoteLocations()
        let savedFolderURLs = restoreSavedFolderURLs()

        if !savedURLs.isEmpty {
            let orderedPaths = UserDefaults.standard.stringArray(forKey: windowOrderKey) ?? []
            let orderedURLs = orderedPaths.compactMap { path -> URL? in
                let url = URL(fileURLWithPath: path)
                return savedURLs.contains(url) ? url : nil
            }
            let remainingURLs = savedURLs.filter { !orderedURLs.contains($0) }
            let allURLsOrdered = orderedURLs + remainingURLs

            for url in allURLsOrdered.reversed() {
                openDocument(url)
            }
        }

        // Restore folder windows with their previously selected files
        let savedSelectedFiles = UserDefaults.standard.dictionary(forKey: folderSelectedFilesKey)
            as? [String: String] ?? [:]
        for url in savedFolderURLs {
            let selectedFile = savedSelectedFiles[url.path].map { URL(fileURLWithPath: $0) }
            openFolder(url, selectedFile: selectedFile)
        }

        // Restore remote documents
        if !savedRemoteLocations.isEmpty {
            restoreRemoteDocuments(savedRemoteLocations)
        } else {
            restoreFrontmostWindow()
        }

        if savedURLs.isEmpty && savedRemoteLocations.isEmpty && savedFolderURLs.isEmpty && !launchedWithFiles {
            showOpenPanel()
        }

        for url in launchURLs {
            documentWindows[url]?.makeKeyAndOrderFront(nil)
        }
    }

    private func restoreOpenRemoteLocations() -> [RemoteLocation] {
        guard let data = UserDefaults.standard.data(forKey: openRemoteLocationsKey) else { return [] }
        // Don't clear yet - cleared after restore completes so failed locations survive app restart
        return (try? JSONDecoder().decode([RemoteLocation].self, from: data)) ?? []
    }

    func applicationWillTerminate(_ notification: Notification) {
        let urls = Array(documentWindows.keys)
        saveOpenURLs(urls)

        // Save open folder URLs and their selected files
        let folderURLs = Array(folderWindows.keys)
        UserDefaults.standard.set(folderURLs.map { $0.path }, forKey: savedFolderURLsKey)
        var selectedFilesDict: [String: String] = [:]
        for (folderURL, fileURL) in folderSelectedFiles {
            selectedFilesDict[folderURL.path] = fileURL.path
        }
        if !selectedFilesDict.isEmpty {
            UserDefaults.standard.set(selectedFilesDict, forKey: folderSelectedFilesKey)
        } else {
            UserDefaults.standard.removeObject(forKey: folderSelectedFilesKey)
        }

        let orderedURLs = NSApp.orderedWindows
            .compactMap { window -> URL? in
                documentWindows.first { $0.value === window }?.key
            }
        UserDefaults.standard.set(orderedURLs.map { $0.path }, forKey: windowOrderKey)

        // Save frontmost window (local, remote, or folder)
        if let frontWindow = NSApp.orderedWindows.first {
            if let localURL = documentWindows.first(where: { $0.value === frontWindow })?.key {
                UserDefaults.standard.set(localURL.path, forKey: frontmostWindowKey)
            } else if let loc = remoteDocumentWindows.first(where: { $0.value === frontWindow })?.key {
                UserDefaults.standard.set("remote:\(loc.host):\(loc.path)", forKey: frontmostWindowKey)
            } else if let folderURL = folderWindows.first(where: { $0.value === frontWindow })?.key {
                UserDefaults.standard.set("folder:\(folderURL.path)", forKey: frontmostWindowKey)
            }
        }

        // Note: Remote locations are saved in applicationShouldTerminate (before windows close)

        BookmarkManager.shared.stopAccessingAll()

        for (_, window) in remoteDocumentWindows {
            window.close()
        }
        remoteDocumentWindows.removeAll()

        Task {
            await SSHConnectionManager.shared.disconnectAll()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Save remote locations BEFORE windows close (windowWillClose clears the dict)
        var allRemoteLocations = Array(remoteDocumentWindows.keys)

        // Merge in any locations that failed to restore (still pending in UserDefaults)
        if let pendingData = UserDefaults.standard.data(forKey: openRemoteLocationsKey),
           let pendingLocations = try? JSONDecoder().decode([RemoteLocation].self, from: pendingData) {
            for location in pendingLocations where !allRemoteLocations.contains(location) {
                allRemoteLocations.append(location)
            }
        }

        print("[AppDelegate] applicationShouldTerminate: saving \(allRemoteLocations.count) remote locations")
        if !allRemoteLocations.isEmpty {
            if let data = try? JSONEncoder().encode(allRemoteLocations) {
                UserDefaults.standard.set(data, forKey: openRemoteLocationsKey)
            }
        } else {
            UserDefaults.standard.removeObject(forKey: openRemoteLocationsKey)
        }
        return .terminateNow
    }

    func restoreFrontmostWindow() {
        guard let saved = UserDefaults.standard.string(forKey: frontmostWindowKey) else { return }
        UserDefaults.standard.removeObject(forKey: frontmostWindowKey)

        if saved.hasPrefix("remote:") {
            // Parse "remote:host:path"
            let rest = String(saved.dropFirst("remote:".count))
            if let colonIdx = rest.firstIndex(of: ":") {
                let host = String(rest[rest.startIndex..<colonIdx])
                let path = String(rest[rest.index(after: colonIdx)...])
                let location = RemoteLocation(host: host, path: path)
                if let window = remoteDocumentWindows[location] {
                    window.makeKeyAndOrderFront(nil)
                }
            }
        } else if saved.hasPrefix("folder:") {
            let path = String(saved.dropFirst("folder:".count))
            let url = URL(fileURLWithPath: path).standardizedFileURL
            if let window = folderWindows[url] {
                window.makeKeyAndOrderFront(nil)
            }
        } else {
            let url = URL(fileURLWithPath: saved)
            if let window = documentWindows[url] {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    @objc private func handleSystemWake(_ notification: Notification) {
        print("[AppDelegate] System woke from sleep, forcing SSH reconnection")
        Task {
            await SSHConnectionManager.shared.forceReconnectAll()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showOpenPanel() }
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        launchedWithFiles = true
        launchURLs = urls
        for url in urls {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                openFolder(url)
            } else {
                openDocument(url)
            }
        }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        launchedWithFiles = true
        launchURLs = [url]
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if isDir.boolValue {
            openFolder(url)
        } else {
            openDocument(url)
        }
        return true
    }

    // MARK: - Window Tracking Updates

    /// Updates the window tracking when navigating to a different file in the same window
    func updateWindowTracking(from oldURL: URL, to newURL: URL) {
        guard let window = documentWindows.removeValue(forKey: oldURL) else { return }
        documentWindows[newURL] = window
        window.title = newURL.displayPath

        // Save current frame under new name BEFORE changing autosave name
        // This prevents setFrameAutosaveName from loading an old stale frame
        let newAutosaveName = newURL.absoluteString
        window.saveFrame(usingName: newAutosaveName)
        window.setFrameAutosaveName(newAutosaveName)

        addToRecentDocuments(newURL)
    }

    /// Updates the window tracking for remote documents when navigating
    func updateRemoteWindowTracking(from oldLocation: RemoteLocation, to newLocation: RemoteLocation) {
        guard let window = remoteDocumentWindows.removeValue(forKey: oldLocation) else { return }
        remoteDocumentWindows[newLocation] = window
        window.title = newLocation.displayTitle

        // Save current frame under new name BEFORE changing autosave name
        // This prevents setFrameAutosaveName from loading an old stale frame
        let newAutosaveName = "remote:\(newLocation.host):\(newLocation.path)"
        window.saveFrame(usingName: newAutosaveName)
        window.setFrameAutosaveName(newAutosaveName)

        addToRecentRemoteLocations(newLocation)
    }

    // MARK: - State Persistence

    private func saveOpenURLs(_ urls: [URL]) {
        UserDefaults.standard.set(urls.map { $0.path }, forKey: savedURLsKey)
    }

    private func restoreSavedURLs() -> [URL] {
        guard let paths = UserDefaults.standard.stringArray(forKey: savedURLsKey) else { return [] }
        return paths.compactMap { path -> URL? in
            let url = URL(fileURLWithPath: path)
            if let resolvedURL = BookmarkManager.shared.resolveBookmark(for: url) {
                if BookmarkManager.shared.startAccessing(resolvedURL) {
                    return resolvedURL
                }
            }
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            return url
        }
    }

    private func restoreSavedFolderURLs() -> [URL] {
        guard let paths = UserDefaults.standard.stringArray(forKey: savedFolderURLsKey) else { return [] }
        UserDefaults.standard.removeObject(forKey: savedFolderURLsKey)
        return paths.compactMap { path -> URL? in
            let url = URL(fileURLWithPath: path)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir),
                  isDir.boolValue else { return nil }
            if let resolvedURL = BookmarkManager.shared.resolveBookmark(for: url) {
                if BookmarkManager.shared.startAccessing(resolvedURL) {
                    return resolvedURL
                }
            }
            return url
        }
    }

    // MARK: - Recent Documents

    func addToRecentDocuments(_ url: URL) {
        recentDocuments.removeAll { $0 == url }
        recentDocuments.insert(url, at: 0)
        if recentDocuments.count > maxRecentDocuments {
            recentDocuments = Array(recentDocuments.prefix(maxRecentDocuments))
        }
        UserDefaults.standard.set(recentDocuments.map { $0.path }, forKey: recentURLsKey)
    }

    private func loadRecentDocuments() -> [URL] {
        guard let paths = UserDefaults.standard.stringArray(forKey: recentURLsKey) else { return [] }
        return paths.compactMap { path -> URL? in
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            return url
        }
    }

    func clearRecentDocuments() {
        recentDocuments = []
        UserDefaults.standard.removeObject(forKey: recentURLsKey)
    }

    func loadRecentRemoteServers() -> [String] {
        UserDefaults.standard.stringArray(forKey: recentRemoteKey) ?? []
    }

    func loadRecentRemoteLocations() -> [RemoteLocation] {
        guard let data = UserDefaults.standard.data(forKey: recentRemoteLocationsKey) else { return [] }
        return (try? JSONDecoder().decode([RemoteLocation].self, from: data)) ?? []
    }

    func saveRecentRemoteLocations() {
        if let data = try? JSONEncoder().encode(recentRemoteLocations) {
            UserDefaults.standard.set(data, forKey: recentRemoteLocationsKey)
        }
    }

    // MARK: - Document Management

    @objc func showOpenPanel() {
        let panel = openPanel
        let keyWindow = NSApp.keyWindow
        if let keyWindow,
           let activeURL = documentWindows.first(where: { $0.value === keyWindow })?.key {
            panel.directoryURL = activeURL.deletingLastPathComponent()
        }

        // Temporarily clear allowedContentTypes so folders aren't grayed out,
        // then restore after panel closes
        panel.allowedContentTypes = []

        NSApp.activate(ignoringOtherApps: true)

        let completionHandler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            panel.allowedContentTypes = [Self.markdownType, .plainText]

            if response == .OK, let url = panel.url {
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                if isDir.boolValue {
                    self?.openFolder(url)
                } else {
                    self?.openDocument(url)
                }
            }
        }

        if let keyWindow {
            panel.beginSheetModal(for: keyWindow, completionHandler: completionHandler)
        } else {
            panel.begin(completionHandler: completionHandler)
        }
    }

    func openDocument(_ url: URL) {
        addToRecentDocuments(url)
        BookmarkManager.shared.createBookmark(for: url)

        if let existingWindow = documentWindows[url] {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let content = (try? String(contentsOf: url, encoding: .utf8)) ?? "Error loading file"

        let documentView = DocumentWindowContent(
            content: content,
            fileURL: url,
            initialScrollPosition: settings.loadScrollPosition(for: url),
            showSidebar: settings.loadSidebarVisible(for: url),
            sidebarWidth: settings.loadSidebarWidth(for: url),
            showGutter: settings.loadGutterVisible(for: url),
            showLineNumbers: settings.loadLineNumbersVisible(for: url),
            showGitIndicators: settings.loadGitIndicatorsVisible(for: url),
            showHiddenFiles: settings.loadHiddenFilesVisible(for: url),
            textWidth: settings.loadTextWidth(for: url),
            contentWidth: settings.loadContentWidth(for: url),
            appDelegate: self,
            onScrollPositionChange: { [weak self] in self?.settings.saveScrollPosition($0, for: url) }
        )

        let window = createWindow(for: url, rootView: documentView)
        documentWindows[url] = window
        window.delegate = self

        // Start hidden, show when content renders
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Listen for content ready notification
        let observerBox = ReferenceBox<NSObjectProtocol?>(nil)
        observerBox.value = NotificationCenter.default.addObserver(
            forName: .windowContentReady,
            object: nil,
            queue: .main
        ) { [weak window] notification in
            guard let notificationURL = notification.userInfo?["fileURL"] as? URL,
                  notificationURL == url else { return }

            // Remove observer after firing
            if let obs = observerBox.value {
                NotificationCenter.default.removeObserver(obs)
            }

            // Fade in window
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                window?.animator().alphaValue = 1
            }
        }
    }

    private func createWindow(for url: URL, rootView: DocumentWindowContent) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: rootView))
        window.title = url.displayPath
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.collectionBehavior = .fullScreenNone
        window.tabbingMode = .disallowed
        window.minSize = NSSize(width: 500, height: 400)

        let autosaveName = url.absoluteString
        let hasSavedFrame = UserDefaults.standard.string(forKey: "NSWindow Frame \(autosaveName)") != nil
        window.setFrameAutosaveName(autosaveName)

        if !hasSavedFrame {
            let size = NSSize(width: 950, height: 1100)
            if let screen = NSScreen.main {
                let origin = NSPoint(
                    x: screen.visibleFrame.midX - size.width / 2,
                    y: screen.visibleFrame.midY - size.height / 2
                )
                window.setFrame(NSRect(origin: origin, size: size), display: false)
            } else {
                window.setContentSize(size)
                window.center()
            }
        }
        return window
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if let folderURL = folderWindows.first(where: { $0.value === window })?.key {
            folderSelectedFiles.removeValue(forKey: folderURL)
        }
        documentWindows = documentWindows.filter { $0.value !== window }
        remoteDocumentWindows = remoteDocumentWindows.filter { $0.value !== window }
        folderWindows = folderWindows.filter { $0.value !== window }
    }

}

// Helper to avoid sendable closure warning with notification observer
private class ReferenceBox<T> {
    var value: T
    init(_ value: T) { self.value = value }
}

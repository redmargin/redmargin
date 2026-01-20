import AppKit
import SwiftUI
import UniformTypeIdentifiers
import RedmarginLib
import RedmarginCore

extension Notification.Name {
    static let toggleLineNumbers = Notification.Name("RedMargin.toggleLineNumbers")
    static let refreshDocument = Notification.Name("RedMargin.refreshDocument")
    static let showFindBar = Notification.Name("RedMargin.showFindBar")
    static let findNext = Notification.Name("RedMargin.findNext")
    static let findPrevious = Notification.Name("RedMargin.findPrevious")
    static let printDocument = Notification.Name("RedMargin.printDocument")
}

extension URL {
    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, ObservableObject {
    private var documentWindows: [URL: NSWindow] = [:]
    private var remoteDocumentWindows: [RemoteLocation: NSWindow] = [:]
    private var launchedWithFiles = false
    private var launchURLs: [URL] = []

    // Cache UTType to avoid repeated LaunchServices lookups
    private static let markdownType = UTType(filenameExtension: "md")!

    // Reuse panel to avoid slow NSOpenPanel initialization
    private lazy var openPanel: NSOpenPanel = {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.markdownType, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.styleMask.insert(.resizable)
        return panel
    }()

    private let savedURLsKey = "RedMargin.OpenDocumentURLs"
    private let recentURLsKey = "RedMargin.RecentDocumentURLs"
    private let recentRemoteKey = "RedMargin.RecentRemoteConnections"
    private let recentRemoteLocationsKey = "RedMargin.RecentRemoteLocations"
    private let windowOrderKey = "RedMargin.WindowOrder"
    private let scrollPositionsKey = "RedMargin.ScrollPositions"
    private let lineNumbersKey = "RedMargin.DocumentLineNumbers"
    private let maxRecentDocuments = 10

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

        // Always restore previously open documents, even when launched via `open -a`.
        // Files opened via command line will appear on top of restored documents.
        let savedURLs = restoreSavedURLs()
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
        } else if !launchedWithFiles {
            showOpenPanel()
        }

        // Bring command-line files to front after restoring other documents
        for url in launchURLs {
            documentWindows[url]?.makeKeyAndOrderFront(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        let urls = Array(documentWindows.keys)
        saveOpenURLs(urls)

        let orderedURLs = NSApp.orderedWindows
            .compactMap { window -> URL? in
                documentWindows.first { $0.value === window }?.key
            }
        UserDefaults.standard.set(orderedURLs.map { $0.path }, forKey: windowOrderKey)

        BookmarkManager.shared.stopAccessingAll()

        // Close all remote document windows gracefully
        for (_, window) in remoteDocumentWindows {
            window.close()
        }
        remoteDocumentWindows.removeAll()

        Task {
            await SSHConnectionManager.shared.disconnectAll()
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
        urls.forEach { openDocument($0) }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        launchedWithFiles = true
        launchURLs = [url]
        openDocument(url)
        return true
    }

    // MARK: - State Persistence

    private func saveOpenURLs(_ urls: [URL]) {
        UserDefaults.standard.set(urls.map { $0.path }, forKey: savedURLsKey)
    }

    private func restoreSavedURLs() -> [URL] {
        guard let paths = UserDefaults.standard.stringArray(forKey: savedURLsKey) else { return [] }
        return paths.compactMap { path -> URL? in
            let url = URL(fileURLWithPath: path)

            // Try to resolve bookmark first for sandboxed access
            if let resolvedURL = BookmarkManager.shared.resolveBookmark(for: url) {
                if BookmarkManager.shared.startAccessing(resolvedURL) {
                    return resolvedURL
                }
            }

            // Fall back to direct file access (works when not sandboxed)
            guard FileManager.default.fileExists(atPath: path) else { return nil }
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
            // Check if file exists (bookmark will be resolved when opening)
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            return url
        }
    }

    func clearRecentDocuments() {
        recentDocuments = []
        UserDefaults.standard.removeObject(forKey: recentURLsKey)
    }

    // MARK: - Document Management

    @objc func showOpenPanel() {
        let panel = openPanel
        let keyWindow = NSApp.keyWindow
        if let keyWindow,
           let activeURL = documentWindows.first(where: { $0.value === keyWindow })?.key {
            panel.directoryURL = activeURL.deletingLastPathComponent()
        }

        NSApp.activate(ignoringOtherApps: true)

        let completionHandler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            if response == .OK, let url = panel.url {
                self?.openDocument(url)
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

        // Create security-scoped bookmark for sandboxed access
        BookmarkManager.shared.createBookmark(for: url)

        if let existingWindow = documentWindows[url] {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let content = (try? String(contentsOf: url, encoding: .utf8))
            ?? "Error loading file"

        let documentView = DocumentWindowContent(
            content: content,
            fileURL: url,
            initialScrollPosition: loadScrollPosition(for: url),
            showLineNumbers: loadLineNumbersVisible(for: url),
            appDelegate: self,
            onScrollPositionChange: { [weak self] in self?.saveScrollPosition($0, for: url) }
        )

        let window = createWindow(for: url, rootView: documentView)
        documentWindows[url] = window
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func createWindow(for url: URL, rootView: DocumentWindowContent) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: rootView))
        window.title = url.displayPath
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
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
        documentWindows = documentWindows.filter { $0.value !== window }
        remoteDocumentWindows = remoteDocumentWindows.filter { $0.value !== window }
    }

    // MARK: - Scroll Position Persistence

    private func saveScrollPosition(_ position: Double, for url: URL) {
        var positions = UserDefaults.standard.dictionary(forKey: scrollPositionsKey) as? [String: Double] ?? [:]
        positions[url.path] = position
        UserDefaults.standard.set(positions, forKey: scrollPositionsKey)
    }

    private func loadScrollPosition(for url: URL) -> Double {
        let positions = UserDefaults.standard.dictionary(forKey: scrollPositionsKey) as? [String: Double] ?? [:]
        return positions[url.path] ?? 0
    }

    // MARK: - Per-Document Line Numbers Persistence

    func saveLineNumbersVisible(_ visible: Bool, for url: URL) {
        var settings = UserDefaults.standard.dictionary(forKey: lineNumbersKey) as? [String: Bool] ?? [:]
        settings[url.path] = visible
        UserDefaults.standard.set(settings, forKey: lineNumbersKey)
    }

    func loadLineNumbersVisible(for url: URL) -> Bool {
        let settings = UserDefaults.standard.dictionary(forKey: lineNumbersKey) as? [String: Bool] ?? [:]
        return settings[url.path] ?? false
    }

    // MARK: - Menu Actions

    @objc func showPreferences(_ sender: Any?) {
        PreferencesWindowController.shared.showWindow(nil)
    }

    @objc func showAbout(_ sender: Any?) {
        let credits = NSAttributedString(
            string: "Markdown viewer with Git diff gutter.",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )

        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationIcon: NSApp.applicationIconImage as Any,
            .applicationName: "Redmargin",
            .applicationVersion: "0.42.0",
            .version: "",
            .credits: credits
        ])
    }

    @objc func printDocument(_ sender: Any?) {
        NotificationCenter.default.post(name: .printDocument, object: nil)
    }

    @objc func showFindBar(_ sender: Any?) {
        NotificationCenter.default.post(name: .showFindBar, object: nil)
    }

    @objc func findNext(_ sender: Any?) {
        NotificationCenter.default.post(name: .findNext, object: nil)
    }

    @objc func findPrevious(_ sender: Any?) {
        NotificationCenter.default.post(name: .findPrevious, object: nil)
    }

    @objc func refreshDocument(_ sender: Any?) {
        NotificationCenter.default.post(name: .refreshDocument, object: nil)
    }

    @objc func toggleLineNumbers(_ sender: Any?) {
        NotificationCenter.default.post(name: .toggleLineNumbers, object: nil)
    }

    // MARK: - Remote Connection

    @objc func showOpenRemoteSheet(_ sender: Any?) {
        var sheetWindow: NSWindow?
        var hostingController: NSHostingController<OpenRemoteSheet>?

        let recentServersBinding = Binding<[String]>(
            get: { [weak self] in self?.recentRemoteServers ?? [] },
            set: { [weak self] newValue in
                self?.recentRemoteServers = newValue
                UserDefaults.standard.set(newValue, forKey: self?.recentRemoteKey ?? "")
            }
        )

        let sheet = OpenRemoteSheet(
            recentServers: recentServersBinding,
            onServerConnected: { [weak self] server in
                self?.addToRecentRemoteServers(server)
            },
            onFileSelected: { [weak self] connection, path in
                try await self?.openRemoteDocument(connection: connection, path: path)
            },
            onDismiss: {
                if let window = sheetWindow {
                    window.close()
                } else if let hc = hostingController,
                          let parent = hc.view.window?.sheetParent {
                    parent.endSheet(hc.view.window!)
                }
            }
        )
        hostingController = NSHostingController(rootView: sheet)

        guard let keyWindow = NSApp.keyWindow ?? NSApp.mainWindow else {
            // No window available, show as standalone window
            let window = NSWindow(contentViewController: hostingController!)
            window.styleMask = [NSWindow.StyleMask.titled, NSWindow.StyleMask.closable]
            window.title = "Open Remote"
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            sheetWindow = window
            return
        }

        keyWindow.contentViewController?.presentAsSheet(hostingController!)
    }

    func openRemoteDocument(connection: SSHConnection, path: String) async throws {
        let host = await connection.getHost()
        let location = RemoteLocation(host: host, path: path)

        // Add to recent lists
        await MainActor.run {
            addToRecentRemoteServers(host)
            addToRecentRemoteLocations(location)
        }

        // Check if already open
        if let existingWindow = remoteDocumentWindows[location] {
            await MainActor.run {
                existingWindow.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
            return
        }

        // Register connection with manager (for reuse)
        await SSHConnectionManager.shared.registerConnection(connection, for: host)

        // Create remote file provider
        let fileProvider = RemoteFileProvider(connection: connection)

        // Read content
        let content = try await fileProvider.readFile(at: path)

        // Create window on main thread
        await MainActor.run {
            let documentView = RemoteDocumentWindowContent(
                content: content,
                location: location,
                fileProvider: fileProvider,
                appDelegate: self
            )

            let window = createRemoteWindow(for: location, rootView: documentView)
            remoteDocumentWindows[location] = window
            window.delegate = self
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func createRemoteWindow(for location: RemoteLocation, rootView: RemoteDocumentWindowContent) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: rootView))
        window.title = location.displayTitle
        window.styleMask = [NSWindow.StyleMask.titled, .closable, .miniaturizable, .resizable]
        window.tabbingMode = NSWindow.TabbingMode.disallowed
        window.minSize = NSSize(width: 500, height: 400)

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
        return window
    }

    // MARK: - Recent Remote Servers

    private func addToRecentRemoteServers(_ server: String) {
        recentRemoteServers.removeAll { $0 == server }
        recentRemoteServers.insert(server, at: 0)
        if recentRemoteServers.count > maxRecentDocuments {
            recentRemoteServers = Array(recentRemoteServers.prefix(maxRecentDocuments))
        }
        UserDefaults.standard.set(recentRemoteServers, forKey: recentRemoteKey)
    }

    private func loadRecentRemoteServers() -> [String] {
        UserDefaults.standard.stringArray(forKey: recentRemoteKey) ?? []
    }

    func clearRecentRemoteServers() {
        recentRemoteServers = []
        UserDefaults.standard.removeObject(forKey: recentRemoteKey)
    }

    // MARK: - Recent Remote Locations

    func addToRecentRemoteLocations(_ location: RemoteLocation) {
        recentRemoteLocations.removeAll { $0 == location }
        recentRemoteLocations.insert(location, at: 0)
        if recentRemoteLocations.count > maxRecentDocuments {
            recentRemoteLocations = Array(recentRemoteLocations.prefix(maxRecentDocuments))
        }
        saveRecentRemoteLocations()
    }

    private func loadRecentRemoteLocations() -> [RemoteLocation] {
        guard let data = UserDefaults.standard.data(forKey: recentRemoteLocationsKey) else { return [] }
        return (try? JSONDecoder().decode([RemoteLocation].self, from: data)) ?? []
    }

    private func saveRecentRemoteLocations() {
        if let data = try? JSONEncoder().encode(recentRemoteLocations) {
            UserDefaults.standard.set(data, forKey: recentRemoteLocationsKey)
        }
    }

    func clearRecentRemoteLocations() {
        recentRemoteLocations = []
        UserDefaults.standard.removeObject(forKey: recentRemoteLocationsKey)
    }

    /// Opens a recent remote location by establishing a new connection
    func openRecentRemoteLocation(_ location: RemoteLocation) {
        Task {
            do {
                let connection = try await SSHConnectionManager.shared.connection(for: location.host)
                try await openRemoteDocument(connection: connection, path: location.path)
            } catch {
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Failed to open remote file"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }
}

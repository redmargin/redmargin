import AppKit
import SwiftUI
import UniformTypeIdentifiers
import RedmarginLib
import RedmarginCore

// Notification.Name and URL extensions are in AppDelegateExtensions.swift

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, ObservableObject {
    private var documentWindows: [URL: NSWindow] = [:]
    var remoteDocumentWindows: [RemoteLocation: NSWindow] = [:]
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
    let recentRemoteKey = "RedMargin.RecentRemoteConnections"
    let recentRemoteLocationsKey = "RedMargin.RecentRemoteLocations"
    private let openRemoteLocationsKey = "RedMargin.OpenRemoteLocations"
    private let windowOrderKey = "RedMargin.WindowOrder"
    private let scrollPositionsKey = "RedMargin.ScrollPositions"
    private let remoteScrollPositionsKey = "RedMargin.RemoteScrollPositions"
    private let lineNumbersKey = "RedMargin.DocumentLineNumbers"
    private let remoteLineNumbersKey = "RedMargin.RemoteDocumentLineNumbers"
    let maxRecentDocuments = 10

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

        let savedURLs = restoreSavedURLs()
        let savedRemoteLocations = restoreOpenRemoteLocations()

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

        // Restore remote documents
        if !savedRemoteLocations.isEmpty {
            Task {
                for location in savedRemoteLocations {
                    do {
                        let connection = SSHConnection(host: location.host)
                        try await connection.connect()
                        try await openRemoteDocument(connection: connection, path: location.path)
                    } catch {
                        print("[AppDelegate] Failed to restore remote document \(location): \(error)")
                    }
                }
            }
        }

        if savedURLs.isEmpty && savedRemoteLocations.isEmpty && !launchedWithFiles {
            showOpenPanel()
        }

        for url in launchURLs {
            documentWindows[url]?.makeKeyAndOrderFront(nil)
        }
    }

    private func restoreOpenRemoteLocations() -> [RemoteLocation] {
        guard let data = UserDefaults.standard.data(forKey: openRemoteLocationsKey) else { return [] }
        // Clear after reading so we don't restore again if app crashes during restore
        UserDefaults.standard.removeObject(forKey: openRemoteLocationsKey)
        return (try? JSONDecoder().decode([RemoteLocation].self, from: data)) ?? []
    }

    func applicationWillTerminate(_ notification: Notification) {
        let urls = Array(documentWindows.keys)
        saveOpenURLs(urls)

        let orderedURLs = NSApp.orderedWindows
            .compactMap { window -> URL? in
                documentWindows.first { $0.value === window }?.key
            }
        UserDefaults.standard.set(orderedURLs.map { $0.path }, forKey: windowOrderKey)

        // Save open remote locations for restoration on next launch
        let openRemoteLocations = Array(remoteDocumentWindows.keys)
        if let data = try? JSONEncoder().encode(openRemoteLocations) {
            UserDefaults.standard.set(data, forKey: openRemoteLocationsKey)
        }

        BookmarkManager.shared.stopAccessingAll()

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
            if let resolvedURL = BookmarkManager.shared.resolveBookmark(for: url) {
                if BookmarkManager.shared.startAccessing(resolvedURL) {
                    return resolvedURL
                }
            }
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
            initialScrollPosition: loadScrollPosition(for: url),
            showLineNumbers: loadLineNumbersVisible(for: url),
            appDelegate: self,
            onScrollPositionChange: { [weak self] in self?.saveScrollPosition($0, for: url) }
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

    func saveScrollPosition(_ position: Double, for location: RemoteLocation) {
        var positions = UserDefaults.standard.dictionary(
            forKey: remoteScrollPositionsKey
        ) as? [String: Double] ?? [:]
        positions[location.storageKey] = position
        UserDefaults.standard.set(positions, forKey: remoteScrollPositionsKey)
    }

    func loadScrollPosition(for location: RemoteLocation) -> Double {
        let positions = UserDefaults.standard.dictionary(
            forKey: remoteScrollPositionsKey
        ) as? [String: Double] ?? [:]
        return positions[location.storageKey] ?? 0
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

    func saveLineNumbersVisible(_ visible: Bool, for location: RemoteLocation) {
        var settings = UserDefaults.standard.dictionary(
            forKey: remoteLineNumbersKey
        ) as? [String: Bool] ?? [:]
        settings[location.storageKey] = visible
        UserDefaults.standard.set(settings, forKey: remoteLineNumbersKey)
    }

    func loadLineNumbersVisible(for location: RemoteLocation) -> Bool {
        let settings = UserDefaults.standard.dictionary(
            forKey: remoteLineNumbersKey
        ) as? [String: Bool] ?? [:]
        return settings[location.storageKey] ?? false
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

    @objc func exportDocument(_ sender: Any?) {
        NotificationCenter.default.post(name: .exportToPDF, object: nil)
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
}

// Helper to avoid sendable closure warning with notification observer
private class ReferenceBox<T> {
    var value: T
    init(_ value: T) { self.value = value }
}

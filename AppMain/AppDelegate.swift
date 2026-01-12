import AppKit
import SwiftUI
import RedmarginLib

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
    private var launchedWithFiles = false

    private let savedURLsKey = "RedMargin.OpenDocumentURLs"
    private let recentURLsKey = "RedMargin.RecentDocumentURLs"
    private let windowOrderKey = "RedMargin.WindowOrder"
    private let scrollPositionsKey = "RedMargin.ScrollPositions"
    private let lineNumbersKey = "RedMargin.DocumentLineNumbers"
    private let maxRecentDocuments = 10

    @Published var recentDocuments: [URL] = []

    override init() {
        super.init()
        recentDocuments = loadRecentDocuments()
    }

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu(target: self)

        if launchedWithFiles { return }

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
        } else {
            showOpenPanel()
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
        urls.forEach { openDocument($0) }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        openDocument(URL(fileURLWithPath: filename))
        return true
    }

    // MARK: - State Persistence

    private func saveOpenURLs(_ urls: [URL]) {
        UserDefaults.standard.set(urls.map { $0.path }, forKey: savedURLsKey)
    }

    private func restoreSavedURLs() -> [URL] {
        guard let paths = UserDefaults.standard.stringArray(forKey: savedURLsKey) else { return [] }
        return paths.compactMap { path in
            FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
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
        return paths.compactMap { path in
            FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
    }

    func clearRecentDocuments() {
        recentDocuments = []
        UserDefaults.standard.removeObject(forKey: recentURLsKey)
    }

    // MARK: - Document Management

    @objc func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if let keyWindow = NSApp.keyWindow,
           let activeURL = documentWindows.first(where: { $0.value === keyWindow })?.key {
            panel.directoryURL = activeURL.deletingLastPathComponent()
        }

        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            openDocument(url)
        }
    }

    func openDocument(_ url: URL) {
        addToRecentDocuments(url)

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
            let size = NSSize(width: 750, height: 1000)
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
            string: "A clean, fast Markdown viewer for macOS.",
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
}

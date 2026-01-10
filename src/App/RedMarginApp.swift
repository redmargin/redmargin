import SwiftUI

@main
struct RedMarginApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            Text("RedMargin")
                .frame(width: 200, height: 100)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    appDelegate.showOpenPanel()
                }
                .keyboardShortcut("o", modifiers: .command)

                Menu("Open Recent") {
                    RecentDocumentsMenu(appDelegate: appDelegate)
                }
                Divider()
            }
        }
    }
}

struct RecentDocumentsMenu: View {
    @ObservedObject var appDelegate: AppDelegate

    var body: some View {
        Group {
            ForEach(appDelegate.recentDocuments, id: \.self) { url in
                Button(url.lastPathComponent) {
                    appDelegate.openDocument(url)
                }
            }
            if appDelegate.recentDocuments.isEmpty {
                Text("No Recent Documents").foregroundColor(.secondary)
            } else {
                Divider()
                Button("Clear Menu") {
                    appDelegate.clearRecentDocuments()
                }
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, ObservableObject {
    private var documentWindows: [URL: NSWindow] = [:]
    private var launchedWithFiles = false

    private let savedURLsKey = "RedMargin.OpenDocumentURLs"
    private let recentURLsKey = "RedMargin.RecentDocumentURLs"
    private let maxRecentDocuments = 10

    @Published var recentDocuments: [URL] = []

    override init() {
        super.init()
        recentDocuments = loadRecentDocuments()
    }

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check if launched with files (set by application(_:open:))
        if launchedWithFiles {
            return
        }

        // Restore previously open documents
        let savedURLs = restoreSavedURLs()
        if !savedURLs.isEmpty {
            for url in savedURLs {
                openDocument(url)
            }
        } else {
            // No saved documents - show Open panel
            showOpenPanel()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Save currently open document URLs
        let urls = Array(documentWindows.keys)
        saveOpenURLs(urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showOpenPanel()
        }
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        launchedWithFiles = true
        for url in urls {
            openDocument(url)
        }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        openDocument(url)
        return true
    }

    // MARK: - State Persistence

    private func saveOpenURLs(_ urls: [URL]) {
        let paths = urls.map { $0.path }
        UserDefaults.standard.set(paths, forKey: savedURLsKey)
    }

    private func restoreSavedURLs() -> [URL] {
        guard let paths = UserDefaults.standard.stringArray(forKey: savedURLsKey) else {
            return []
        }
        return paths.compactMap { path in
            let url = URL(fileURLWithPath: path)
            // Only restore if file still exists
            return FileManager.default.fileExists(atPath: path) ? url : nil
        }
    }

    // MARK: - Recent Documents

    func addToRecentDocuments(_ url: URL) {
        // Remove if already exists (will be re-added at front)
        recentDocuments.removeAll { $0 == url }

        // Add to front
        recentDocuments.insert(url, at: 0)

        // Trim to max
        if recentDocuments.count > maxRecentDocuments {
            recentDocuments = Array(recentDocuments.prefix(maxRecentDocuments))
        }

        // Save
        let paths = recentDocuments.map { $0.path }
        UserDefaults.standard.set(paths, forKey: recentURLsKey)
    }

    private func loadRecentDocuments() -> [URL] {
        guard let paths = UserDefaults.standard.stringArray(forKey: recentURLsKey) else {
            return []
        }
        return paths.compactMap { path in
            let url = URL(fileURLWithPath: path)
            return FileManager.default.fileExists(atPath: path) ? url : nil
        }
    }

    func clearRecentDocuments() {
        recentDocuments = []
        UserDefaults.standard.removeObject(forKey: recentURLsKey)
    }

    // MARK: - Document Management

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            openDocument(url)
        }
    }

    func openDocument(_ url: URL) {
        addToRecentDocuments(url)

        // Bring existing window to front if already open
        if let existingWindow = documentWindows[url] {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Load content
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            content = "Error loading file: \(error.localizedDescription)"
        }

        // Create SwiftUI view wrapped in hosting controller
        let documentView = DocumentWindowContent(content: content, fileURL: url)
        let hostingController = NSHostingController(rootView: documentView)

        // Create window
        let window = NSWindow(contentViewController: hostingController)
        window.title = url.lastPathComponent
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.minSize = NSSize(width: 500, height: 400)

        // Set frame autosave name for persistence
        let autosaveName = url.absoluteString
        let frameKey = "NSWindow Frame \(autosaveName)"
        let hasSavedFrame = UserDefaults.standard.string(forKey: frameKey) != nil

        window.setFrameAutosaveName(autosaveName)

        // Set default size and position if no saved frame
        if !hasSavedFrame {
            let size = NSSize(width: 750, height: 1000)
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let origin = NSPoint(
                    x: screenFrame.midX - size.width / 2,
                    y: screenFrame.midY - size.height / 2
                )
                window.setFrame(NSRect(origin: origin, size: size), display: false)
            } else {
                window.setContentSize(size)
                window.center()
            }
        }

        // Track window and set delegate for cleanup
        documentWindows[url] = window
        window.delegate = self

        // Show window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        documentWindows = documentWindows.filter { $0.value !== window }
    }
}

struct DocumentWindowContent: View {
    let content: String
    let fileURL: URL

    var body: some View {
        MarkdownWebView(markdown: content, fileURL: fileURL)
            .frame(minWidth: 500, idealWidth: 750, minHeight: 400, idealHeight: 1000)
    }
}

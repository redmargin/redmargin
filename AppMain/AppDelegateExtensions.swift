import AppKit
import SwiftUI
import RedmarginCore

// MARK: - Notification Names

extension Notification.Name {
    static var toggleSidebar: Notification.Name { Notification.Name("RedMargin.toggleSidebar") }
    static var toggleLineNumbers: Notification.Name { Notification.Name("RedMargin.toggleLineNumbers") }
    static var toggleGutter: Notification.Name { Notification.Name("RedMargin.toggleGutter") }
    static var toggleGitIndicators: Notification.Name { Notification.Name("RedMargin.toggleGitIndicators") }
    static var refreshDocument: Notification.Name { Notification.Name("RedMargin.refreshDocument") }
    static var showFindBar: Notification.Name { Notification.Name("RedMargin.showFindBar") }
    static var findNext: Notification.Name { Notification.Name("RedMargin.findNext") }
    static var findPrevious: Notification.Name { Notification.Name("RedMargin.findPrevious") }
    static var printDocument: Notification.Name { Notification.Name("RedMargin.printDocument") }
    static var exportToPDF: Notification.Name { Notification.Name("RedMargin.exportToPDF") }
    static var windowContentReady: Notification.Name { Notification.Name("RedMargin.windowContentReady") }
}

// MARK: - URL Display Path

extension URL {
    internal var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

// MARK: - AppDelegate Remote Connection

extension AppDelegate {
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
            onFolderSelected: { [weak self] connection, path in
                try await self?.openRemoteFolder(connection: connection, path: path)
            },
            onDismiss: {
                if let window = sheetWindow {
                    window.close()
                } else if let hostCtrl = hostingController,
                          let parent = hostCtrl.view.window?.sheetParent {
                    parent.endSheet(hostCtrl.view.window!)
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
                showSidebar: settings.loadSidebarVisible(for: location),
                sidebarWidth: settings.loadSidebarWidth(for: location),
                appDelegate: self
            )

            let window = createRemoteWindow(for: location, rootView: documentView)
            remoteDocumentWindows[location] = window
            window.delegate = self
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Opens a remote directory as a folder window with sidebar
    func openRemoteFolder(connection: SSHConnection, path: String) async throws {
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

        // Register connection with manager
        await SSHConnectionManager.shared.registerConnection(connection, for: host)

        // Create remote file provider
        let fileProvider = RemoteFileProvider(connection: connection)

        await MainActor.run {
            let folderView = RemoteDocumentWindowContent(
                folderPath: path,
                host: host,
                fileProvider: fileProvider,
                showSidebar: true,
                sidebarWidth: settings.loadSidebarWidth(for: location),
                appDelegate: self
            )

            let window = createRemoteWindow(for: location, rootView: folderView)
            remoteDocumentWindows[location] = window
            window.delegate = self
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Opens a remote document from sidebar navigation, reusing the existing connection
    func openRemoteDocumentFromSidebar(host: String, path: String) async throws {
        let location = RemoteLocation(host: host, path: path)

        // Add to recent lists
        await MainActor.run {
            addToRecentRemoteLocations(location)
        }

        // Check if already open
        if let existingWindow = remoteDocumentWindows[location] {
            await MainActor.run {
                existingWindow.makeKeyAndOrderFront(nil)
            }
            return
        }

        // Get existing connection from manager
        let connection = try await SSHConnectionManager.shared.connection(for: host)

        // Create file provider and read content
        let fileProvider = RemoteFileProvider(connection: connection)
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
        }
    }

    func createRemoteWindow(for location: RemoteLocation, rootView: RemoteDocumentWindowContent) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: rootView))
        window.title = location.displayTitle
        window.styleMask = [NSWindow.StyleMask.titled, .closable, .miniaturizable, .resizable]
        window.collectionBehavior = .fullScreenNone
        window.tabbingMode = NSWindow.TabbingMode.disallowed
        window.minSize = NSSize(width: 500, height: 400)

        let autosaveName = "remote:\(location.host):\(location.path)"
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

    // MARK: - Recent Remote Servers

    func addToRecentRemoteServers(_ server: String) {
        recentRemoteServers.removeAll { $0 == server }
        recentRemoteServers.insert(server, at: 0)
        if recentRemoteServers.count > maxRecentDocuments {
            recentRemoteServers = Array(recentRemoteServers.prefix(maxRecentDocuments))
        }
        UserDefaults.standard.set(recentRemoteServers, forKey: recentRemoteKey)
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

    func clearRecentRemoteLocations() {
        recentRemoteLocations = []
        UserDefaults.standard.removeObject(forKey: recentRemoteLocationsKey)
    }

    /// Opens a recent remote location by establishing a new connection
    func openRecentRemoteLocation(_ location: RemoteLocation) {
        Task {
            do {
                // Quick check if file or directory exists before establishing full connection
                let sshArgs = [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    location.host,
                    "test -e '\(location.path)'"
                ]
                let checkResult = try await ProcessRunner.run(
                    executable: "/usr/bin/ssh",
                    arguments: sshArgs,
                    timeout: 10
                )
                if checkResult.exitCode != 0 {
                    throw RemoteFileError(message: "File does not exist", code: .fileNotFound)
                }

                let connection = try await SSHConnectionManager.shared.connection(for: location.host)

                // Check if it's a directory
                let isDirArgs = [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=5",
                    location.host,
                    "test -d '\(location.path)'"
                ]
                let isDirResult = try await ProcessRunner.run(
                    executable: "/usr/bin/ssh",
                    arguments: isDirArgs,
                    timeout: 10
                )
                if isDirResult.exitCode == 0 {
                    try await openRemoteFolder(connection: connection, path: location.path)
                } else {
                    try await openRemoteDocument(connection: connection, path: location.path)
                }
            } catch {
                await MainActor.run {
                    let isFileNotFound = (error as? RemoteFileError)?.isFileNotFound == true

                    let alert = NSAlert()

                    if isFileNotFound {
                        // Remove from recents since file no longer exists
                        recentRemoteLocations.removeAll { $0 == location }
                        saveRecentRemoteLocations()

                        alert.messageText = "File Not Found"
                        let remotePath = "\(location.host):\(location.path)"
                        alert.informativeText = """
                            The file no longer exists at:
                            \(remotePath)

                            It has been removed from Recent Documents.
                            """
                    } else {
                        alert.messageText = "Failed to open remote file"
                        alert.informativeText = error.localizedDescription
                    }

                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }
}

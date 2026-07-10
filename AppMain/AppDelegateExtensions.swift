import AppKit
import SwiftUI
import RedmarginCore

// MARK: - Notification Names

extension Notification.Name {
    static var toggleSidebar: Notification.Name { Notification.Name("RedMargin.toggleSidebar") }
    static var toggleLineNumbers: Notification.Name { Notification.Name("RedMargin.toggleLineNumbers") }
    static var toggleGutter: Notification.Name { Notification.Name("RedMargin.toggleGutter") }
    static var toggleGitIndicators: Notification.Name { Notification.Name("RedMargin.toggleGitIndicators") }
    static var toggleHiddenFiles: Notification.Name { Notification.Name("RedMargin.toggleHiddenFiles") }
    static var refreshDocument: Notification.Name { Notification.Name("RedMargin.refreshDocument") }
    static var showFindBar: Notification.Name { Notification.Name("RedMargin.showFindBar") }
    static var findNext: Notification.Name { Notification.Name("RedMargin.findNext") }
    static var findPrevious: Notification.Name { Notification.Name("RedMargin.findPrevious") }
    static var printDocument: Notification.Name { Notification.Name("RedMargin.printDocument") }
    static var exportToPDF: Notification.Name { Notification.Name("RedMargin.exportToPDF") }
    static var windowContentReady: Notification.Name { Notification.Name("RedMargin.windowContentReady") }
    static var setTextWidth: Notification.Name { Notification.Name("RedMargin.setTextWidth") }
    static var setContentWidth: Notification.Name { Notification.Name("RedMargin.setContentWidth") }
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
            },
            onReleaseConnection: { [weak self] host in
                await self?.releaseRemoteConnectionIfUnused(host: host)
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

    /// Drops a host's connection once nothing is using it. Called when the remote
    /// open sheet is cancelled: its connection is the manager's, shared with every
    /// window on that host, so it can only be closed when no window remains.
    func releaseRemoteConnectionIfUnused(host: String) async {
        let stillInUse = await MainActor.run {
            self.remoteDocumentWindows.keys.contains { $0.host == host }
        }
        guard !stillInUse else { return }
        await SSHConnectionManager.shared.disconnect(host: host)
    }

    func openRemoteDocument(connection: SSHConnection, path: String) async throws {
        let host = await connection.getHost()
        let location = RemoteLocation(host: host, path: path)
        await MainActor.run { recordRemoteDocumentRecent(host: host, path: path) }

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
        let content = try await readRemoteDocumentContent(
            fileProvider: fileProvider,
            path: path
        )

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
        let folderPath = path.hasSuffix("/") ? path : path + "/"
        let location = RemoteLocation(host: host, path: folderPath)
        await MainActor.run { recordRemoteFolderRecent(host: host, path: folderPath) }

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
                folderPath: folderPath,
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

    func recordRemoteDocumentRecent(host: String, path: String) {
        addToRecentRemoteServers(host)
        recentWorkspaces.add(.remoteFile(RemoteLocation(host: host, path: path)))
    }

    func recordRemoteFolderRecent(host: String, path: String) {
        addToRecentRemoteServers(host)
        recentWorkspaces.add(.remoteFolder(RemoteLocation(host: host, path: path)))
    }

    /// Opens a remote document from sidebar navigation, reusing the existing connection
    func openRemoteDocumentFromSidebar(host: String, path: String) async throws {
        let location = RemoteLocation(host: host, path: path)

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
        let content = try await readRemoteDocumentContent(
            fileProvider: fileProvider,
            path: path
        )

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

    /// Builds a remote window from cached content without connecting. The host's
    /// connection is preregistered (created but not yet connected) so the window and
    /// its file provider exist before any network work; the window starts in the
    /// `.onDemand` phase and connects lazily via `connectIfNeeded`. Folder locations
    /// (trailing slash) build a folder window whose tree loads once connected.
    /// The window is registered but returned unordered, so the caller places it.
    @MainActor
    func makeOnDemandRemoteWindow(location: RemoteLocation, cachedContent: String) async -> NSWindow {
        let connection = await SSHConnectionManager.shared.preregisterConnection(for: location.host)
        let fileProvider = RemoteFileProvider(connection: connection)

        let rootView: RemoteDocumentWindowContent
        if location.path.hasSuffix("/") {
            rootView = RemoteDocumentWindowContent(
                folderPath: location.path,
                host: location.host,
                fileProvider: fileProvider,
                showSidebar: true,
                sidebarWidth: settings.loadSidebarWidth(for: location),
                connectsOnDemand: true,
                appDelegate: self
            )
        } else {
            rootView = RemoteDocumentWindowContent(
                content: cachedContent,
                location: location,
                fileProvider: fileProvider,
                showSidebar: settings.loadSidebarVisible(for: location),
                sidebarWidth: settings.loadSidebarWidth(for: location),
                connectsOnDemand: true,
                appDelegate: self
            )
        }

        let window = createRemoteWindow(for: location, rootView: rootView)
        remoteDocumentWindows[location] = window
        window.delegate = self
        return window
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
        RedmarginWindowToolbar.install(on: window)
        return window
    }

    // MARK: - Recent Remote Servers

    func addToRecentRemoteServers(_ server: String) {
        recentRemoteServers.removeAll { $0 == server }
        recentRemoteServers.insert(server, at: 0)
        if recentRemoteServers.count > maxRecentItems {
            recentRemoteServers = Array(recentRemoteServers.prefix(maxRecentItems))
        }
        UserDefaults.standard.set(recentRemoteServers, forKey: recentRemoteKey)
    }

    func clearRecentRemoteServers() {
        recentRemoteServers = []
        UserDefaults.standard.removeObject(forKey: recentRemoteKey)
    }

    func openRecentWorkspace(_ item: RecentWorkspaceItem) {
        switch item.kind {
        case .localFile:
            guard let url = item.localURL else { return }
            openDocument(url)
        case .localFolder:
            guard let url = item.localURL else { return }
            openFolder(url, selectedFile: savedSelectedFile(for: url))
        case .remoteFile:
            guard let location = item.remoteLocation else { return }
            openRecentRemoteFile(location, item: item)
        case .remoteFolder:
            guard let location = item.remoteLocation else { return }
            openRecentRemoteLocation(location, item: item)
        }
    }

    @discardableResult
    func retryRecentWorkspace(_ item: RecentWorkspaceItem) async -> Bool {
        switch item.kind {
        case .localFile, .localFolder:
            await MainActor.run {
                openRecentWorkspace(item)
            }
            return true
        case .remoteFile:
            guard let location = item.remoteLocation else { return false }
            return await performRecentRemoteFileOpen(location, item: item, showsAlert: false)
        case .remoteFolder:
            guard let location = item.remoteLocation else { return false }
            return await performRecentRemoteFolderOpen(location, item: item, showsAlert: false)
        }
    }

    func locateRecentWorkspace(_ item: RecentWorkspaceItem) {
        guard item.localURL != nil else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = item.kind == .localFolder
        panel.canChooseFiles = item.kind == .localFile
        if item.kind == .localFile {
            panel.allowedContentTypes = [Self.markdownType, .plainText]
        }
        panel.directoryURL = item.localURL?.deletingLastPathComponent()

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.recentWorkspaces.relocate(item, to: url)
        }
    }

    /// Opens a recent remote folder by establishing a new connection
    func openRecentRemoteLocation(_ location: RemoteLocation) {
        openRecentRemoteLocation(location, item: .remoteFolder(location))
    }

    @discardableResult
    func openRecentRemoteLocation(
        _ location: RemoteLocation,
        item: RecentWorkspaceItem,
        showsAlert: Bool = true
    ) -> Task<Void, Never> {
        Task {
            let succeeded = await performRecentRemoteFolderOpen(location, item: item, showsAlert: showsAlert)
            if succeeded {
                await MainActor.run {
                    recentWorkspaces.clearRemoteFailure(item)
                }
            }
        }
    }

    /// Single-quotes a remote path for safe use in a shell command while leaving
    /// a leading `~` or `~user` segment unquoted so the remote shell still expands
    /// it to the home directory. Single quotes would otherwise suppress tilde
    /// expansion, making `test -d '~/foo'` look for a literal `~/foo` directory.
    static func shellArgPreservingTilde(_ path: String) -> String {
        func singleQuoted(_ s: String) -> String {
            "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        guard path.hasPrefix("~") else { return singleQuoted(path) }

        // Only a genuine tilde prefix may travel unquoted: `~`, or `~` followed by a
        // login name. Everything that reaches the remote shell unquoted has to be
        // spelled out here, or a path like `~;id` or `~a;id/notes` carries a command
        // into `test -d`. A path that merely starts with `~` is quoted whole; it
        // would not have expanded to a home directory anyway.
        let userPart = path.dropFirst().prefix { $0 != "/" }
        let isLoginName = userPart.allSatisfy { char in
            char.isASCII && (char.isLetter || char.isNumber || char == "_" || char == "-" || char == ".")
        }
        guard isLoginName else { return singleQuoted(path) }

        guard let slash = path.firstIndex(of: "/") else {
            // Bare `~` or `~user` with no path component: safe to expand.
            return path
        }
        // Keep the `~`/`~user` prefix and the separating slash unquoted; quote the rest.
        let prefix = String(path[...slash])
        let rest = String(path[path.index(after: slash)...])
        return rest.isEmpty ? prefix : prefix + singleQuoted(rest)
    }

    @discardableResult
    private func performRecentRemoteFolderOpen(
        _ location: RemoteLocation,
        item: RecentWorkspaceItem,
        showsAlert: Bool
    ) async -> Bool {
        do {
                // Open Recent is folder-only; remove entries that are gone or no longer directories.
            let sshArgs = [
                "-o", "BatchMode=yes",
                "-o", "ConnectTimeout=5",
                location.host,
                "test -d \(Self.shellArgPreservingTilde(location.path))"
            ]
            let checkResult = try await ProcessRunner.run(
                executable: "/usr/bin/ssh",
                arguments: sshArgs,
                timeout: 10
            )
            // ssh exits 255 on its own connection/auth failures; only the remote
            // command's own non-zero exit means the folder is genuinely absent.
            if checkResult.exitCode == 255 {
                let reason = checkResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                throw RemoteFileError(
                    message: reason.isEmpty ? "Could not connect to \(location.host)" : reason,
                    code: .connectionFailed
                )
            }
            if checkResult.exitCode != 0 {
                throw RemoteFileError(message: "Folder does not exist", code: .fileNotFound)
            }

            let connection = try await SSHConnectionManager.shared.connection(for: location.host)
            try await openRemoteFolder(connection: connection, path: location.path)
            return true
        } catch {
            await handleRecentRemoteFailure(error, item: item, messageText: "Failed to open remote folder", showsAlert: showsAlert)
            return false
        }
    }

    @discardableResult
    private func openRecentRemoteFile(
        _ location: RemoteLocation,
        item: RecentWorkspaceItem,
        showsAlert: Bool = true
    ) -> Task<Void, Never> {
        Task {
            let succeeded = await performRecentRemoteFileOpen(location, item: item, showsAlert: showsAlert)
            if succeeded {
                await MainActor.run {
                    recentWorkspaces.clearRemoteFailure(item)
                }
            }
        }
    }

    @discardableResult
    private func performRecentRemoteFileOpen(
        _ location: RemoteLocation,
        item: RecentWorkspaceItem,
        showsAlert: Bool
    ) async -> Bool {
        do {
            let connection = try await SSHConnectionManager.shared.connection(for: location.host)
            try await openRemoteDocument(connection: connection, path: location.path)
            return true
        } catch {
            await handleRecentRemoteFailure(error, item: item, messageText: "Failed to open remote file", showsAlert: showsAlert)
            return false
        }
    }

    @MainActor
    private func handleRecentRemoteFailure(
        _ error: Error,
        item: RecentWorkspaceItem,
        messageText: String,
        showsAlert: Bool
    ) {
        recentWorkspaces.markRemoteFailure(item, reason: error.localizedDescription)
        guard showsAlert else { return }

        let alert = NSAlert()
        alert.messageText = messageText
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

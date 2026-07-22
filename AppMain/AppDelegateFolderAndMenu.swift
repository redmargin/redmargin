import AppKit
import SwiftUI
import RedmarginLib
import RedmarginCore

// MARK: - Folder Management

extension AppDelegate {
    func openFolder(_ url: URL, selectedFile: URL? = nil) {
        let standardized = url.standardizedFileURL
        recentWorkspaces.add(.localFolder(standardized))

        if let existingWindow = folderWindows[standardized] {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        BookmarkManager.shared.createBookmark(for: standardized)

        let folderView = FolderWindowContent(
            folderURL: standardized,
            initialSelectedFile: selectedFile,
            showSidebar: settings.loadSidebarVisible(for: standardized),
            sidebarWidth: settings.loadSidebarWidth(for: standardized),
            showHiddenFiles: settings.loadHiddenFilesVisible(for: standardized),
            appDelegate: self
        )

        let window = createFolderWindow(for: standardized, rootView: folderView)
        folderWindows[standardized] = window
        persistOpenFolderURLs()
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func createFolderWindow(for url: URL, rootView: FolderWindowContent) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: rootView))
        window.title = url.displayPath
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.collectionBehavior = .fullScreenNone
        window.tabbingMode = .disallowed
        window.minSize = NSSize(width: 500, height: 400)

        let autosaveName = "folder:\(url.path)"
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

    /// Called by FolderWindowContent when a file is selected
    func updateFolderWindowFile(folder folderURL: URL, to fileURL: URL?) {
        let standardized = folderURL.standardizedFileURL
        if let fileURL {
            folderSelectedFiles[standardized] = fileURL.standardizedFileURL
            saveFolderSelectedFiles()
        } else {
            folderSelectedFiles.removeValue(forKey: standardized)
            clearSavedSelectedFile(for: standardized)
        }
    }
}

// MARK: - Remote Document Restore

extension AppDelegate {
    /// Restores remote windows instantly and passively: every saved window is built
    /// from its locally cached last-seen contents with no network round-trip, placed
    /// in saved back-to-front z-order without stealing focus, then connected lazily
    /// (the frontmost first, the rest via a background warm pass / on focus).
    func restoreRemoteDocuments(_ savedRemoteLocations: [RemoteLocation]) {
        print("[AppDelegate] Restoring \(savedRemoteLocations.count) remote windows (on-demand)")
        guard !savedRemoteLocations.isEmpty else {
            restoreFrontmostWindow()
            return
        }

        Task { @MainActor in
            // Saved back-to-front z-order and frontmost, as storage keys.
            let savedOrderTokens = UserDefaults.standard.stringArray(forKey: remoteWindowOrderKey) ?? []
            let savedOrderKeys = savedOrderTokens.compactMap(RemoteRestoreOrdering.storageKey(fromWindowToken:))
            let frontmostKey = UserDefaults.standard.string(forKey: frontmostWindowKey)
                .flatMap(PersistedWindowIdentity.decode)?
                .remoteLocation?.storageKey

            let plan = RemoteRestoreOrdering.plan(
                locations: savedRemoteLocations,
                savedOrderKeys: savedOrderKeys,
                frontmostKey: frontmostKey
            )

            // Build every window from cache (no network), keyed by location.
            var windows: [RemoteLocation: NSWindow] = [:]
            for location in plan.placementOrder {
                let cached = RemoteContentCache.shared.loadSync(for: location) ?? ""
                let window = await makeOnDemandRemoteWindow(location: location, cachedContent: cached)
                windows[location] = window
            }

            // Place passively in back-to-front order: orderFront the first window,
            // then order(.above:) each subsequent one. Never makeKeyAndOrderFront,
            // never NSApp.activate — that is what stole focus on restore.
            var previous: NSWindow?
            for location in plan.placementOrder {
                guard let window = windows[location] else { continue }
                if let previous {
                    window.order(.above, relativeTo: previous.windowNumber)
                } else {
                    window.orderFront(nil)
                }
                previous = window
            }

            // Single key-window decision for the whole launch stays here.
            restoreFrontmostWindow()

            // The previously active remote window connects immediately; the rest warm
            // quietly in the background and on focus.
            if let frontmost = plan.keyLocation {
                NotificationCenter.default.post(
                    name: .remoteWindowConnectRequest, object: frontmost.storageKey
                )
            }
            startBackgroundRemoteWarm(skipping: plan.keyLocation)
        }
    }
}

// MARK: - Menu Actions

extension AppDelegate {
    @objc func showPreferences(_ sender: Any?) {
        PreferencesWindowController.shared.showWindow(sender)
    }

    @objc func showAbout(_ sender: Any?) {
        let description = "Markdown viewer with Git change indicators, syntax highlighting, " +
            "file sidebar, remote file access over SSH, and PDF export."
        let credits = NSAttributedString(
            string: description,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )

        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationIcon: NSApp.applicationIconImage as Any,
            .applicationName: "Redmargin",
            .applicationVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            .version: "",
            .credits: credits
        ])
    }

    @objc func showRecentWorkspaces(_ sender: Any?) {
        RecentWorkspacesWindowController.show(store: recentWorkspaces, appDelegate: self)
    }

    @objc func showCommandPaletteFromMenu(_ sender: NSMenuItem) {
        showCommandPalette()
    }

    func showCommandPalette() {
        CommandPaletteWindowController.show(appDelegate: self)
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

    @objc func toggleGutter(_ sender: Any?) {
        NotificationCenter.default.post(name: .toggleGutter, object: nil)
    }

    @objc func toggleGitIndicators(_ sender: Any?) {
        NotificationCenter.default.post(name: .toggleGitIndicators, object: nil)
    }

    @objc func toggleHiddenFiles(_ sender: Any?) {
        NotificationCenter.default.post(name: .toggleHiddenFiles, object: nil)
    }

    @objc func toggleSidebar(_ sender: Any?) {
        NotificationCenter.default.post(name: .toggleSidebar, object: nil)
    }

    @objc func setTextWidth(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        NotificationCenter.default.post(name: .setTextWidth, object: nil, userInfo: ["value": value])
    }

    @objc func setContentWidth(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        NotificationCenter.default.post(name: .setContentWidth, object: nil, userInfo: ["value": value])
    }
}

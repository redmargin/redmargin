import AppKit
import SwiftUI
import RedmarginLib
import RedmarginCore

// MARK: - Folder Management

extension AppDelegate {
    func openFolder(_ url: URL, selectedFile: URL? = nil) {
        let standardized = url.standardizedFileURL
        addToRecentFolder(standardized)

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
    func restoreRemoteDocuments(_ savedRemoteLocations: [RemoteLocation]) {
        print("[AppDelegate] Restoring \(savedRemoteLocations.count) remote documents")
        Task {
            var failedLocations: [RemoteLocation] = []
            let retryDelays: [UInt64] = [0, 3_000_000_000, 5_000_000_000]  // 0s, 3s, 5s

            // Group by host to share SSH connections
            let locationsByHost = Dictionary(grouping: savedRemoteLocations, by: \.host)

            for (host, locations) in locationsByHost {
                var connection: SSHConnection?

                for (attempt, delay) in retryDelays.enumerated() {
                    if delay > 0 {
                        try? await Task.sleep(nanoseconds: delay)
                    }
                    do {
                        connection = try await SSHConnectionManager.shared.connection(for: host)
                        break
                    } catch {
                        let maxAttempts = retryDelays.count
                        print("[AppDelegate] Connection to \(host) failed " +
                              "(attempt \(attempt + 1)/\(maxAttempts)): \(error)")
                    }
                }

                guard let conn = connection else {
                    print("[AppDelegate] Giving up on \(host) after \(retryDelays.count) attempts")
                    failedLocations.append(contentsOf: locations)
                    continue
                }

                for location in locations {
                    do {
                        // Check if path exists and whether it is a directory
                        let remoteCheck = "test -e '\(location.path)' && "
                            + "{ test -d '\(location.path)' && echo dir || echo file; } "
                            + "|| echo missing"
                        let existsArgs = [
                            "-o", "BatchMode=yes",
                            "-o", "ConnectTimeout=5",
                            location.host,
                            remoteCheck
                        ]
                        let existsResult = try await ProcessRunner.run(
                            executable: "/usr/bin/ssh",
                            arguments: existsArgs,
                            timeout: 10
                        )
                        let kind = existsResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                        if kind == "missing" {
                            print("[AppDelegate] Dropping stale restore entry (path gone): \(location.path)")
                            continue
                        }
                        if kind == "dir" {
                            try await openRemoteFolder(connection: conn, path: location.path)
                        } else {
                            try await openRemoteDocument(connection: conn, path: location.path)
                        }
                        print("[AppDelegate] Restored: \(location.path)")
                    } catch let error as RemoteFileError where error.isFileNotFound {
                        print("[AppDelegate] Dropping stale restore entry (not found): \(location.path)")
                    } catch {
                        print("[AppDelegate] Failed to restore \(location): \(error)")
                        failedLocations.append(location)
                    }
                }
            }

            // Clear the restore key now that all attempts are done
            UserDefaults.standard.removeObject(forKey: self.openRemoteLocationsKey)

            // Save failed locations back so they're retried on next launch
            if !failedLocations.isEmpty {
                let count = failedLocations.count
                print("[AppDelegate] \(count) remote documents failed to restore, saving for next launch")
                if let data = try? JSONEncoder().encode(failedLocations) {
                    UserDefaults.standard.set(data, forKey: self.openRemoteLocationsKey)
                }
            }

            // Restore frontmost window after all remote docs are loaded
            await MainActor.run {
                self.restoreFrontmostWindow()
            }
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

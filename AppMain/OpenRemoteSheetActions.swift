import SwiftUI
import RedmarginCore

/// Result of initial directory load attempt
struct InitialDirectoryResult {
    let path: String
    let entries: [DirectoryEntry]
    let useFallback: Bool
}

// MARK: - Navigation Actions

extension OpenRemoteSheet {
    func handleEnterKey() -> KeyPress.Result {
        if connection != nil && !isLoadingDirectory {
            guard let index = selectedFileIndex else { return .ignored }
            if index == -1 {
                navigateUp()
                return .handled
            } else if index >= 0 && index < entries.count {
                selectEntry(entries[index])
                return .handled
            }
        }
        return .ignored
    }

    func handleArrowNavigation(_ direction: NavDirection) -> KeyPress.Result {
        if connection == nil && !isConnecting && !recentServers.isEmpty {
            return handleServerNavigation(direction)
        }
        if connection != nil && !isLoadingDirectory {
            return handleFileNavigation(direction)
        }
        return .ignored
    }

    private func handleServerNavigation(_ direction: NavDirection) -> KeyPress.Result {
        switch direction {
        case .downward:
            if let current = selectedServerIndex {
                selectedServerIndex = min(current + 1, recentServers.count - 1)
            } else {
                selectedServerIndex = 0
            }
        case .upward:
            if let current = selectedServerIndex {
                selectedServerIndex = max(current - 1, 0)
            } else {
                selectedServerIndex = recentServers.count - 1
            }
        }
        if let index = selectedServerIndex {
            serverName = recentServers[index]
        }
        return .handled
    }

    private func handleFileNavigation(_ direction: NavDirection) -> KeyPress.Result {
        let hasParent = currentPath != "/" && !currentPath.isEmpty
        let minIndex = hasParent ? -1 : 0
        let maxIndex = entries.count - 1

        guard maxIndex >= minIndex else { return .ignored }

        switch direction {
        case .downward:
            if let current = selectedFileIndex {
                selectedFileIndex = min(current + 1, maxIndex)
            } else {
                selectedFileIndex = minIndex
            }
        case .upward:
            if let current = selectedFileIndex {
                selectedFileIndex = max(current - 1, minIndex)
            } else {
                selectedFileIndex = maxIndex
            }
        }
        return .handled
    }
}

// MARK: - Connection Actions

extension OpenRemoteSheet {
    func connectToServer() {
        let host = serverName.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return }

        isConnecting = true
        connectionStatus = "Connecting to"
        errorMessage = nil

        Task {
            do {
                let conn = SSHConnection(host: host)
                await MainActor.run { onServerConnected(host) }

                try await conn.connect(onProgress: { status in
                    Task { @MainActor in self.connectionStatus = status }
                })

                let homeDir = try await conn.getHomeDirectory()
                let result = await tryLoadInitialDirectory(conn, homeDir: homeDir)

                await MainActor.run {
                    self.connection = conn
                    self.currentPath = result.path
                    self.pathInput = result.path
                    self.entries = result.entries
                    self.pathHistory = []
                    self.isConnecting = false
                    self.usePathEntry = result.useFallback
                    self.selectedFileIndex = nil
                    self.isPathFieldFocused = true
                }
            } catch {
                await MainActor.run {
                    self.isConnecting = false
                    self.errorMessage = formatError(error)
                }
            }
        }
    }

    private func tryLoadInitialDirectory(
        _ conn: SSHConnection,
        homeDir: String
    ) async -> InitialDirectoryResult {
        // Try /opt first
        do {
            let entries = try await withTimeout(seconds: 5) {
                try await conn.listDirectory(path: "/opt")
            }
            return InitialDirectoryResult(path: "/opt", entries: entries, useFallback: false)
        } catch {
            // Fall back to home directory
            do {
                let entries = try await withTimeout(seconds: 5) {
                    try await conn.listDirectory(path: homeDir)
                }
                return InitialDirectoryResult(path: homeDir, entries: entries, useFallback: false)
            } catch {
                return InitialDirectoryResult(path: homeDir, entries: [], useFallback: true)
            }
        }
    }

    func disconnectAndGoBack() {
        Task { await connection?.disconnect() }
        connection = nil
        entries = []
        currentPath = ""
        pathInput = ""
        pathHistory = []
        errorMessage = nil
    }

    func dismissSheet() {
        Task { await connection?.disconnect() }
        onDismiss()
    }
}

// MARK: - File Browser Actions

extension OpenRemoteSheet {
    func selectEntry(_ entry: DirectoryEntry) {
        if entry.isDirectory {
            navigateToDirectory(entry.name)
        } else {
            openFile(entry.name)
        }
    }

    func navigateToDirectory(_ name: String) {
        let newPath = currentPath == "~" ? "~/\(name)" : "\(currentPath)/\(name)"
        pathHistory.append(currentPath)
        loadDirectory(newPath)
    }

    func navigateUp() {
        if let previousPath = pathHistory.popLast() {
            loadDirectory(previousPath)
        } else {
            let parent = (currentPath as NSString).deletingLastPathComponent
            if !parent.isEmpty && parent != currentPath {
                loadDirectory(parent)
            }
        }
    }

    func navigateToPath(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        pathHistory = [currentPath]
        loadDirectory(trimmed)
    }

    func loadDirectory(_ path: String) {
        guard let conn = connection else { return }

        isLoadingDirectory = true
        errorMessage = nil
        selectedFileIndex = nil

        Task {
            do {
                let dirEntries = try await conn.listDirectory(path: path)
                await MainActor.run {
                    self.currentPath = path
                    self.pathInput = path
                    self.entries = dirEntries
                    self.isLoadingDirectory = false
                    self.selectedFileIndex = nil
                }
            } catch {
                await MainActor.run {
                    self.isLoadingDirectory = false
                    self.errorMessage = "Failed to load directory: \(error.localizedDescription)"
                }
            }
        }
    }

    func openFile(_ name: String) {
        guard let conn = connection else { return }

        let fullPath = currentPath == "~" ? "~/\(name)" : "\(currentPath)/\(name)"

        Task {
            do {
                try await onFileSelected(conn, fullPath)
                await MainActor.run { onDismiss() }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to open file: \(error.localizedDescription)"
                }
            }
        }
    }

    func openManualPath() {
        let path = manualPath.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty, let conn = connection else { return }

        let fullPath: String
        if path.hasPrefix("~/") {
            fullPath = currentPath + String(path.dropFirst(1))
        } else if path == "~" {
            fullPath = currentPath
        } else if path.hasPrefix("/") {
            fullPath = path
        } else {
            fullPath = currentPath + "/" + path
        }

        Task {
            do {
                try await onFileSelected(conn, fullPath)
                await MainActor.run { onDismiss() }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to open file: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Helpers

extension OpenRemoteSheet {
    func formatError(_ error: Error) -> String {
        let message = error.localizedDescription

        if message.contains("Permission denied") || message.contains("publickey") {
            return "SSH authentication failed. Ensure you have SSH keys configured for this host."
        }
        if message.contains("Connection refused") || message.contains("No route to host") {
            return "Could not connect to host. Verify the hostname and that SSH is running."
        }
        if message.contains("Could not resolve hostname") {
            return "Unknown host. Check the hostname or verify it's in your ~/.ssh/config."
        }
        return "Connection failed: \(message)"
    }

    func fileIcon(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "md", "markdown": return "doc.text"
        case "txt": return "doc.plaintext"
        default: return "doc"
        }
    }

    func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

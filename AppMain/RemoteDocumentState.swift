import Foundation
import RedmarginLib
import RedmarginCore

/// Represents a pending checkbox toggle that couldn't be saved due to disconnect
struct PendingCheckboxToggle {
    let line: Int
    let checked: Bool
    let contentBeforeToggle: String
    let contentAfterToggle: String
}

@MainActor
class RemoteDocumentState: ObservableObject {
    @Published var content: String
    @Published var gitChanges: GitChangeResult?
    @Published var isRefreshing: Bool = false
    @Published var connectionState: SSHConnectionState = .connected

    /// When true, shows conflict resolution dialog
    @Published var showConflictDialog: Bool = false

    let location: RemoteLocation
    private let fileProvider: RemoteFileProvider

    private var fileWatchToken: WatchToken?
    private var gitWatchToken: WatchToken?
    private var isWritingFile = false

    private var repoRoot: String?
    private var gitChangeTask: Task<Void, Never>?
    private var stateObserverTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?

    /// Last content that was confirmed on the server (read or successfully written)
    private var lastKnownServerContent: String

    /// Pending checkbox toggle that failed due to disconnect
    private var pendingToggle: PendingCheckboxToggle?

    init(content: String, location: RemoteLocation, fileProvider: RemoteFileProvider) {
        self.content = content
        self.lastKnownServerContent = content
        self.location = location
        self.fileProvider = fileProvider
        Task {
            await setupFileWatcher()
            await detectGitChanges()
            await startObservingConnectionState()
        }
    }

    deinit {
        let provider = fileProvider
        let fToken = fileWatchToken
        let gToken = gitWatchToken
        stateObserverTask?.cancel()
        Task {
            if let token = fToken { await provider.unwatch(token) }
            if let token = gToken { await provider.unwatch(token) }
        }
    }

    private func startObservingConnectionState() async {
        stateObserverTask = Task { [weak self] in
            guard let self = self else { return }
            for await newState in self.fileProvider.stateChanges {
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    self.handleConnectionStateChange(newState)
                }
            }
        }
    }

    private func handleConnectionStateChange(_ newState: SSHConnectionState) {
        let oldState = connectionState
        connectionState = newState

        print("[RemoteDocumentState] Connection state: \(oldState) -> \(newState)")

        // Handle reconnection
        if oldState == .reconnecting && newState == .connected {
            handleReconnection()
        }
    }

    private func handleReconnection() {
        print("[RemoteDocumentState] Reconnected, checking for conflicts...")

        Task {
            do {
                let serverContent = try await fileProvider.readFile(at: location.path)

                await MainActor.run {
                    // Check if server content changed while we were disconnected
                    let serverChanged = serverContent != lastKnownServerContent

                    if let pending = pendingToggle {
                        if serverChanged {
                            // Conflict: server changed AND we have pending toggle
                            print("[RemoteDocumentState] Conflict - server changed with pending toggle")
                            showConflictDialog = true
                        } else {
                            // No conflict: apply pending toggle
                            print("[RemoteDocumentState] No conflict, applying pending toggle")
                            applyPendingToggle(pending)
                        }
                    } else {
                        // No pending toggle, just update content if changed
                        if serverChanged {
                            print("[RemoteDocumentState] Server content changed, updating")
                            content = serverContent
                            lastKnownServerContent = serverContent
                            Task {
                                await detectGitChanges()
                            }
                        }
                    }
                }
            } catch {
                print("[RemoteDocumentState] Failed to read file on reconnect: \(error)")
            }
        }
    }

    private func applyPendingToggle(_ pending: PendingCheckboxToggle) {
        guard let toggle = pendingToggle else { return }

        Task {
            do {
                try await fileProvider.writeFile(at: location.path, content: toggle.contentAfterToggle)
                await MainActor.run {
                    content = toggle.contentAfterToggle
                    lastKnownServerContent = toggle.contentAfterToggle
                    pendingToggle = nil
                    print("[RemoteDocumentState] Pending toggle applied successfully")
                }
            } catch {
                print("[RemoteDocumentState] Failed to apply pending toggle: \(error)")
                // Keep the pending toggle for next reconnect attempt
            }
        }
    }

    /// Called when user chooses "Overwrite Local Toggle" in conflict dialog
    func resolveConflictKeepLocalToggle() {
        guard let pending = pendingToggle else {
            showConflictDialog = false
            return
        }

        Task {
            do {
                try await fileProvider.writeFile(at: location.path, content: pending.contentAfterToggle)
                await MainActor.run {
                    content = pending.contentAfterToggle
                    lastKnownServerContent = pending.contentAfterToggle
                    pendingToggle = nil
                    showConflictDialog = false
                    print("[RemoteDocumentState] Conflict resolved: kept local toggle")
                    Task {
                        await detectGitChanges()
                    }
                }
            } catch {
                print("[RemoteDocumentState] Failed to save local toggle: \(error)")
                await MainActor.run {
                    showConflictDialog = false
                }
            }
        }
    }

    /// Called when user chooses "Reload from Server" in conflict dialog
    func resolveConflictReloadFromServer() {
        Task {
            do {
                let serverContent = try await fileProvider.readFile(at: location.path)
                await MainActor.run {
                    content = serverContent
                    lastKnownServerContent = serverContent
                    pendingToggle = nil
                    showConflictDialog = false
                    print("[RemoteDocumentState] Conflict resolved: reloaded from server")
                    Task {
                        await detectGitChanges()
                    }
                }
            } catch {
                print("[RemoteDocumentState] Failed to reload from server: \(error)")
                await MainActor.run {
                    showConflictDialog = false
                }
            }
        }
    }

    private func setupFileWatcher() async {
        if let token = fileWatchToken { await fileProvider.unwatch(token) }

        fileWatchToken = await fileProvider.watchFile(at: location.path) { [weak self] in
            Task { @MainActor in
                self?.reloadContent()
            }
        }
    }

    private func reloadContent() {
        guard !isWritingFile else {
            print("[RemoteDocumentState] Skipping reload during self-initiated write")
            return
        }

        // Cancel any pending reload to prevent races
        reloadTask?.cancel()

        print("[RemoteDocumentState] reloadContent called for \(location.displayString)")
        reloadTask = Task {
            do {
                let newContent = try await fileProvider.readFile(at: location.path)

                // Check if cancelled (a write started while we were reading)
                guard !Task.isCancelled else {
                    print("[RemoteDocumentState] Reload cancelled (write started during read)")
                    return
                }

                await MainActor.run {
                    guard newContent != content else {
                        print("[RemoteDocumentState] Content unchanged, skipping update")
                        return
                    }
                    print("[RemoteDocumentState] Content changed, updating (\(newContent.count) chars)")
                    content = newContent
                    lastKnownServerContent = newContent
                    Task {
                        await detectGitChanges()
                    }
                }
            } catch {
                if !Task.isCancelled {
                    print("[RemoteDocumentState] Failed to read file: \(error)")
                }
            }
        }
    }

    func refresh() {
        isRefreshing = true
        Task {
            if let newContent = try? await fileProvider.readFile(at: location.path) {
                await MainActor.run {
                    content = newContent
                    lastKnownServerContent = newContent
                }
            }
            await detectGitChanges()

            try? await Task.sleep(nanoseconds: 300_000_000)
            await MainActor.run {
                self.isRefreshing = false
            }
        }
    }

    private func detectGitChanges() async {
        print("[RemoteGutter] detectGitChanges called for \(location.displayString)")

        gitChangeTask?.cancel()

        gitChangeTask = Task { @MainActor in
            do {
                guard !Task.isCancelled else { return }

                if repoRoot == nil {
                    repoRoot = try await fileProvider.detectGitRepo(for: location.path)
                    print("[RemoteGutter] Detected repo root: \(repoRoot ?? "nil")")

                    if let root = repoRoot {
                        await setupGitWatcher(root: root)
                    }
                }

                guard let root = repoRoot else {
                    gitChanges = nil
                    return
                }

                guard !Task.isCancelled else { return }

                let changes = try await fileProvider.gitDiff(for: location.path, repoRoot: root)

                guard !Task.isCancelled else { return }

                if gitChanges != changes {
                    gitChanges = changes
                }
            } catch {
                if !Task.isCancelled {
                    print("[RemoteGutter] Error detecting changes: \(error)")
                    gitChanges = nil
                }
            }
        }
    }

    private func setupGitWatcher(root: String) async {
        if let token = gitWatchToken { await fileProvider.unwatch(token) }

        gitWatchToken = await fileProvider.watchGitRepo(at: root) { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                await self.detectGitChanges()
            }
        }
    }

    func readAsset(path: String) async throws -> (Data, String) {
        try await fileProvider.readAsset(at: path)
    }

    func handleCheckboxToggle(line: Int, checked: Bool) {
        // Optimistic UI - update locally first
        var lines = content.components(separatedBy: "\n")
        let index = line - 1

        guard index >= 0 && index < lines.count else { return }

        let currentLine = lines[index]
        let newLine: String

        if checked {
            newLine = currentLine
                .replacingOccurrences(of: "- [ ]", with: "- [x]")
                .replacingOccurrences(of: "* [ ]", with: "* [x]")
                .replacingOccurrences(of: "+ [ ]", with: "+ [x]")
        } else {
            newLine = currentLine
                .replacingOccurrences(of: "- [x]", with: "- [ ]")
                .replacingOccurrences(of: "- [X]", with: "- [ ]")
                .replacingOccurrences(of: "* [x]", with: "* [ ]")
                .replacingOccurrences(of: "* [X]", with: "* [ ]")
                .replacingOccurrences(of: "+ [x]", with: "+ [ ]")
                .replacingOccurrences(of: "+ [X]", with: "+ [ ]")
        }

        guard newLine != currentLine else { return }

        lines[index] = newLine
        let newContent = lines.joined(separator: "\n")

        // Cancel any pending reload - we're about to write
        reloadTask?.cancel()
        reloadTask = nil

        // Update locally immediately (optimistic)
        let oldContent = content
        isWritingFile = true
        content = newContent

        // Send to server
        Task {
            defer {
                Task { @MainActor in
                    self.isWritingFile = false
                }
            }

            do {
                try await fileProvider.writeFile(at: location.path, content: newContent)
                // Success - update last known server content
                await MainActor.run {
                    lastKnownServerContent = newContent
                    pendingToggle = nil
                }
            } catch {
                print("[RemoteDocumentState] Failed to save checkbox toggle: \(error)")

                // Check if we're disconnected
                let currentState = await fileProvider.getConnectionState()
                await MainActor.run {
                    if currentState == .reconnecting || currentState == .disconnected {
                        // Cache the pending toggle for reconnection
                        print("[RemoteDocumentState] Caching pending toggle for reconnection")
                        pendingToggle = PendingCheckboxToggle(
                            line: line,
                            checked: checked,
                            contentBeforeToggle: oldContent,
                            contentAfterToggle: newContent
                        )
                        // Keep the optimistic UI update
                    } else {
                        // Other error - revert
                        content = oldContent
                    }
                }
            }
        }
    }
}

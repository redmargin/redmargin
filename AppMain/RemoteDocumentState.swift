import Foundation
import Observation
import os.log
import RedmarginLib
import RedmarginCore

private let refreshLog = Logger(subsystem: "com.redmargin", category: "RemoteRefresh")

/// Represents a pending checkbox toggle that couldn't be saved due to disconnect
struct PendingCheckboxToggle {
    let line: Int
    let checked: Bool
    let contentBeforeToggle: String
    let contentAfterToggle: String
}

@MainActor
@Observable
class RemoteDocumentState {
    var content: String
    var gitChanges: GitChangeResult?
    var isRefreshing: Bool = false
    var refreshToken: Int = 0  // Sole purpose: bust image cache in MarkdownWebView
    var connectionState: SSHConnectionState = .connected

    /// When true, shows conflict resolution dialog
    var showConflictDialog: Bool = false

    private(set) var location: RemoteLocation
    @ObservationIgnored let fileProvider: RemoteFileProvider

    @ObservationIgnored private var fileWatchToken: WatchToken?
    @ObservationIgnored private var gitWatchToken: WatchToken?
    @ObservationIgnored private var isWritingFile = false

    @ObservationIgnored private var repoRoot: String?
    @ObservationIgnored private var gitChangeTask: Task<Void, Never>?
    @ObservationIgnored private var stateObserverTask: Task<Void, Never>?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var reconnectObserver: Any?

    /// Last content that was confirmed on the server (read or successfully written)
    @ObservationIgnored private var lastKnownServerContent: String

    /// Pending checkbox toggle that failed due to disconnect
    @ObservationIgnored private var pendingToggle: PendingCheckboxToggle?

    init(content: String, location: RemoteLocation, fileProvider: RemoteFileProvider) {
        self.content = content
        self.lastKnownServerContent = content
        self.location = location
        self.fileProvider = fileProvider

        // Observe reconnection via NotificationCenter (reliable, unlike AsyncStream).
        // Filter by host to prevent cross-host cascading reconnection loops.
        let reconnectHost = location.host
        reconnectObserver = NotificationCenter.default.addObserver(
            forName: .sshConnectionReconnected,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let host = notification.object as? String,
                  host == reconnectHost else { return }
            Task { @MainActor in
                self.handleReconnection()
            }
        }

        Task {
            await SSHConnectionManager.shared.beginRemoteDocumentActivity()
            async let watcher: Void = setupFileWatcher()
            async let git: Void = detectGitChanges()
            _ = await (watcher, git)
            await startObservingConnectionState()
        }
    }

    deinit {
        if let observer = reconnectObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        let provider = fileProvider
        let fToken = fileWatchToken
        let gToken = gitWatchToken
        stateObserverTask?.cancel()
        Task {
            if let token = fToken { await provider.unwatch(token) }
            if let token = gToken { await provider.unwatch(token) }
            await SSHConnectionManager.shared.endRemoteDocumentActivity()
        }
    }

    private func startObservingConnectionState() async {
        let stateStream = fileProvider.stateChanges
        stateObserverTask = Task { [weak self] in
            for await newState in stateStream {
                guard !Task.isCancelled, let self = self else { break }
                await MainActor.run {
                    self.handleConnectionStateChange(newState)
                }
            }
        }
    }

    private func handleConnectionStateChange(_ newState: SSHConnectionState) {
        let oldState = connectionState
        connectionState = newState

        let old = String(describing: oldState)
        let new = String(describing: newState)
        refreshLog.info("connectionState: \(old, privacy: .public) -> \(new, privacy: .public)")
        // Note: handleReconnection() is triggered by the NotificationCenter observer,
        // not here. The AsyncStream is used only for UI state (overlay).
    }

    private func handleReconnection() {
        refreshLog.info("handleReconnection() called")

        // Clear the "Connecting" overlay immediately
        connectionState = .connected
        refreshToken += 1

        Task {
            // Re-register file watcher — old server-side watcher may be stale
            // (daemon restarted) or duplicated. setupFileWatcher unwatches the
            // old token first, and server-side dedup handles any leftovers.
            await setupFileWatcher()

            // Re-register git watcher if we had one
            if let root = repoRoot {
                await setupGitWatcher(root: root)
            }

            do {
                let serverContent = try await fileProvider.readFile(at: location.path)

                await MainActor.run {
                    let serverChanged = serverContent != lastKnownServerContent

                    if let pending = pendingToggle {
                        if serverChanged {
                            refreshLog.info("Conflict — server changed with pending toggle")
                            showConflictDialog = true
                        } else {
                            refreshLog.info("No conflict, applying pending toggle")
                            applyPendingToggle(pending)
                        }
                    } else if serverChanged {
                        refreshLog.info("Server content changed, updating")
                        content = serverContent
                        lastKnownServerContent = serverContent
                        Task { await detectGitChanges() }
                    } else {
                        refreshLog.info("Content unchanged after reconnect")
                    }
                }
            } catch {
                refreshLog.error("Failed to read file on reconnect: \(error)")
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

        // Cancel any pending reload — acts as debounce since the new task
        // waits 300ms before reading, giving rapid events time to coalesce.
        reloadTask?.cancel()

        reloadTask = Task {
            // Debounce: wait for events to settle (atomic writes, editor saves)
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }

            refreshLog.info("reloadContent reading \(self.location.displayString)")
            do {
                let newContent = try await fileProvider.readFile(at: location.path)

                // Check if cancelled (a write started while we were reading)
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard newContent != content else {
                        refreshLog.info("reloadContent: content unchanged")
                        return
                    }
                    refreshLog.info("reloadContent: content changed (\(newContent.count) chars)")
                    content = newContent
                    lastKnownServerContent = newContent
                    Task {
                        await detectGitChanges()
                    }
                }
            } catch {
                if !Task.isCancelled {
                    refreshLog.error("reloadContent failed: \(error)")
                }
            }
        }
    }

    func refresh() {
        isRefreshing = true
        refreshLog.info("refresh() starting for \(self.location.path)")
        Task {
            var succeeded = false

            // If connection has been idle, verify it's still alive before
            // triggering the full refresh (which also refreshes the sidebar).
            // This avoids a 30s hang on stale connections.
            let idle = await fileProvider.connectionIdleTime()
            if idle > 30 {
                refreshLog.info("refresh() idle \(idle)s, pinging first")
                let alive = await pingConnection()
                if !alive {
                    refreshLog.info("refresh() ping failed, forcing reconnect")
                    await fileProvider.forceReconnect()
                    succeeded = await waitForReconnectAndRetryRead()
                }
            }

            // Normal read (skipped if we already reconnected above)
            if !succeeded {
                refreshToken += 1
                do {
                    let newContent = try await fileProvider.readFile(at: location.path)
                    await MainActor.run {
                        content = newContent
                        lastKnownServerContent = newContent
                    }
                    succeeded = true
                    refreshLog.info("refresh() read succeeded")
                } catch {
                    refreshLog.error("refresh() read failed: \(error), forcing reconnect")
                    await fileProvider.forceReconnect()
                    succeeded = await waitForReconnectAndRetryRead()
                }
            }

            if succeeded {
                // Sync connectionState from the actual connection — the AsyncStream
                // observer can lag behind, leaving the "Connecting" overlay stuck.
                let actualState = await fileProvider.getConnectionState()
                if connectionState != actualState {
                    let was = String(describing: self.connectionState)
                    let now = String(describing: actualState)
                    refreshLog.info(
                        "refresh() fixing stale connectionState: \(was, privacy: .public) -> \(now, privacy: .public)"
                    )
                    connectionState = actualState
                }
                await detectGitChanges()
            }

            try? await Task.sleep(nanoseconds: 300_000_000)
            refreshLog.info("refresh() done, clearing spinner (succeeded=\(succeeded))")
            await MainActor.run {
                self.isRefreshing = false
            }
        }
    }

    /// Waits up to 20s for the connection to come back, then retries the read once.
    private func waitForReconnectAndRetryRead() async -> Bool {
        refreshLog.info("waitForReconnect: waiting for connection...")
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            let connState = await fileProvider.getConnectionState()
            if connState == .connected {
                refreshLog.info("waitForReconnect: connected, retrying read")
                break
            }
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
        }

        do {
            let newContent = try await fileProvider.readFile(at: location.path)
            await MainActor.run {
                content = newContent
                lastKnownServerContent = newContent
            }
            refreshLog.info("waitForReconnect: retry succeeded")
            return true
        } catch {
            refreshLog.error("waitForReconnect: retry failed: \(error)")
            return false
        }
    }

    /// Quick ping to verify the connection is responsive (no side effects if it fails)
    private func pingConnection() async -> Bool {
        await fileProvider.ping(timeout: 3)
    }

    /// Loads a different file in the same window
    func loadFile(at path: String) async throws {
        // If connection has been idle, verify it's alive before reading
        let idle = await fileProvider.connectionIdleTime()
        if idle > 30 {
            let alive = await pingConnection()
            if !alive {
                await fileProvider.forceReconnect()
                let deadline = Date().addingTimeInterval(15)
                while Date() < deadline {
                    let state = await fileProvider.getConnectionState()
                    if state == .connected { break }
                    try await Task.sleep(nanoseconds: 500_000_000)
                }
            }
        }

        let newContent = try await fileProvider.readFile(at: path)

        // Update location and content
        location = RemoteLocation(host: location.host, path: path)
        content = newContent
        lastKnownServerContent = newContent
        gitChanges = nil
        repoRoot = nil
        pendingToggle = nil
        refreshToken += 1

        // Reset watchers for the new file
        await setupFileWatcher()
        await detectGitChanges()
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
        let newLine = toggleCheckbox(in: currentLine, checked: checked)

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

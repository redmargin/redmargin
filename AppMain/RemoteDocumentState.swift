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

/// Presentation phase for a remote window, independent of the live transport state.
/// Drives the inline status overlay and gates file-watch/git startup until the
/// connection is live. A restored, not-yet-connected window starts in `.onDemand`.
enum RemoteConnectionPhase: Equatable {
    case onDemand
    case connecting
    case connected
    case unavailable(RemoteUnavailableReason)
}

/// Why a remote window could not be connected. Drives the inline message and
/// whether a Retry control is offered.
enum RemoteUnavailableReason: Equatable {
    case noRoute
    case refused
    case authFailed
    case fileNotFound
    case serverError

    /// Pure mapping from a terminal connect error to its inline reason. Hard
    /// failures get their specific reason; everything else is a generic server error.
    static func forConnectError(_ error: SSHConnectionError) -> RemoteUnavailableReason {
        switch error {
        case .hostUnreachable: return .noRoute
        case .connectionRefused: return .refused
        case .authenticationFailed: return .authFailed
        default: return .serverError
        }
    }
}

@MainActor
@Observable
class RemoteDocumentState {
    var content: String
    var gitChanges: GitChangeResult?
    var isRefreshing: Bool = false
    var refreshToken: Int = 0  // Sole purpose: bust image cache in MarkdownWebView
    var connectionState: SSHConnectionState = .connected

    /// Presentation phase that drives the inline status overlay. Distinct from
    /// `connectionState` (live transport): the overlay reads `connectionPhase`.
    var connectionPhase: RemoteConnectionPhase = .connected

    /// When true, shows conflict resolution dialog
    var showConflictDialog: Bool = false

    private(set) var location: RemoteLocation
    @ObservationIgnored let fileProvider: RemoteFileProvider
    @ObservationIgnored let contentCache: RemoteContentCache

    /// Guards the single transition out of `.onDemand`/`.unavailable` into a connect.
    @ObservationIgnored var isConnecting = false

    /// True once the App Nap activity token has been taken (i.e. the window went
    /// live). An on-demand window that never connects must not release a token it
    /// never acquired, so `deinit` checks this before ending the activity.
    @ObservationIgnored var didBeginActivity = false

    @ObservationIgnored private var fileWatchToken: WatchToken?
    @ObservationIgnored private var gitWatchToken: WatchToken?
    @ObservationIgnored private var isWritingFile = false

    @ObservationIgnored private var repoRoot: String?
    @ObservationIgnored private var gitChangeTask: Task<Void, Never>?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var reconnectObserver: Any?
    @ObservationIgnored private var connectRequestObserver: Any?
    @ObservationIgnored private var stateChangeObserver: Any?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    /// Last content that was confirmed on the server (read or successfully written)
    @ObservationIgnored var lastKnownServerContent: String

    /// Pending checkbox toggle that failed due to disconnect
    @ObservationIgnored private var pendingToggle: PendingCheckboxToggle?

    /// - Parameters:
    ///   - connectsOnDemand: When true, the window is restored from cache and does
    ///     no network work (no App Nap token, file watcher, git detection, or
    ///     connection-state observation) until `connectIfNeeded` is called; it
    ///     starts in `.onDemand`. When false (current callers), behavior is
    ///     unchanged and the window starts `.connected`.
    ///   - contentCache: Local last-seen-content cache; injectable for tests.
    init(
        content: String,
        location: RemoteLocation,
        fileProvider: RemoteFileProvider,
        connectsOnDemand: Bool = false,
        contentCache: RemoteContentCache = .shared
    ) {
        self.content = content
        self.lastKnownServerContent = content
        self.location = location
        self.fileProvider = fileProvider
        self.contentCache = contentCache
        self.connectionPhase = connectsOnDemand ? .onDemand : .connected

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

        // Observe explicit connect requests for this window's location (T9). Lets
        // the frontmost-connect, background warm, and focus paths drive a connect
        // without holding a reference to this state object.
        let requestKey = location.storageKey
        connectRequestObserver = NotificationCenter.default.addObserver(
            forName: .remoteWindowConnectRequest,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  (notification.object as? String) == requestKey else { return }
            Task { @MainActor in
                await self.connectIfNeeded()
            }
        }

        // Mirror live transport state into the presentation phase for this window.
        // Driven by the host-filtered broadcast, not the connection's single-consumer
        // `stateChanges` stream: every window on a host shares one connection, and the
        // stream would deliver each transition to only one of them, stranding the rest
        // of the windows' "Connecting…" overlay. The phase guard in
        // handleConnectionStateChange keeps an .onDemand/.unavailable window untouched,
        // so registering this before the window goes live is safe.
        let stateHost = location.host
        stateChangeObserver = NotificationCenter.default.addObserver(
            forName: .sshConnectionStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  (notification.object as? String) == stateHost,
                  let newState = notification.userInfo?["state"] as? SSHConnectionState
            else { return }
            Task { @MainActor in
                self.handleConnectionStateChange(newState)
            }
        }

        if connectsOnDemand {
            // Stay passive until connectIfNeeded — no network work.
        } else {
            // Content was just read from the server, so it is confirmed: cache it.
            cacheContent(content)
            Task { await startLiveConnectionWork() }
        }
    }

    deinit {
        if let observer = reconnectObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = connectRequestObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = stateChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        let provider = fileProvider
        let fToken = fileWatchToken
        let gToken = gitWatchToken
        refreshTask?.cancel()
        reloadTask?.cancel()
        gitChangeTask?.cancel()
        let began = didBeginActivity
        Task {
            if let token = fToken { await provider.unwatch(token) }
            if let token = gToken { await provider.unwatch(token) }
            if began { await SSHConnectionManager.shared.endRemoteDocumentActivity() }
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

        // Mirror live transport into the presentation phase (T8) once the window
        // is live. An .onDemand or .unavailable window's phase is owned by
        // connectIfNeeded, so it is left untouched here.
        switch connectionPhase {
        case .connecting, .connected:
            switch newState {
            case .connected:
                connectionPhase = .connected
            case .connecting, .reconnecting, .disconnected:
                connectionPhase = .connecting
            }
        case .onDemand, .unavailable:
            break
        }
    }

    @discardableResult
    func applyServerContent(_ newContent: String, for expectedPath: String) -> Bool {
        guard location.path == expectedPath else { return false }
        content = newContent
        lastKnownServerContent = newContent
        cacheContent(newContent)
        return true
    }

    /// Reconcile a freshly-read server content during connect revalidation,
    /// honoring a pending checkbox toggle exactly like reconnection does: a server
    /// change under a pending toggle raises the existing conflict prompt; otherwise
    /// the pending toggle is applied or the server change is taken (A8).
    func revalidateWithServerContent(_ serverContent: String, for path: String) {
        guard location.path == path else { return }
        let serverChanged = serverContent != lastKnownServerContent

        if let pending = pendingToggle {
            if serverChanged {
                refreshLog.info("Conflict on connect — server changed with pending toggle")
                showConflictDialog = true
            } else {
                applyPendingToggle(pending)
            }
        } else if serverChanged {
            applyServerContent(serverContent, for: path)
            Task { await detectGitChanges() }
        }
    }

    /// Persist confirmed server content to the local cache, fire-and-forget so it
    /// never blocks the UI. Empty content (folder windows) is not cached.
    func cacheContent(_ content: String) {
        guard !content.isEmpty else { return }
        let location = self.location
        let cache = contentCache
        Task.detached(priority: .utility) {
            await cache.save(content, for: location)
        }
    }

    private func handleReconnection() {
        refreshLog.info("handleReconnection() called")
        let path = location.path

        // Clear the "Connecting" overlay immediately. The overlay reads
        // connectionPhase, so repair that too — repairing only connectionState left
        // the pill stuck after a reconnect.
        connectionState = .connected
        if connectionPhase == .connecting {
            connectionPhase = .connected
        }
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
                let serverContent = try await readRemoteDocumentContent(
                    fileProvider: fileProvider,
                    path: path,
                    pingFirst: false
                )

                await MainActor.run {
                    guard self.location.path == path else { return }
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
        let path = location.path
        Task {
            do {
                let serverContent = try await readRemoteDocumentContent(
                    fileProvider: fileProvider,
                    path: path,
                    pingFirst: true
                )
                await MainActor.run {
                    guard self.applyServerContent(serverContent, for: path) else { return }
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

    func setupFileWatcher() async {
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
            let path = self.location.path

            refreshLog.info("reloadContent reading \(self.location.displayString)")
            do {
                let newContent = try await readRemoteDocumentContent(
                    fileProvider: fileProvider,
                    path: path,
                    pingFirst: false
                )

                // Check if cancelled (a write started while we were reading)
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard self.location.path == path else { return }
                    guard newContent != content else {
                        refreshLog.info("reloadContent: content unchanged")
                        return
                    }
                    refreshLog.info("reloadContent: content changed (\(newContent.count) chars)")
                    guard self.applyServerContent(newContent, for: path) else { return }
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
        refreshTask?.cancel()
        isRefreshing = true
        refreshLog.info("refresh() starting for \(self.location.path)")
        let path = location.path

        refreshToken += 1
        refreshTask = Task {
            var succeeded = false

            do {
                let newContent = try await readRemoteDocumentContent(
                    fileProvider: fileProvider,
                    path: path,
                    pingFirst: true,
                    interactive: true,
                    fullTimeout: RemoteOperationSupport.interactiveFullTimeout,
                    reconnectWaitTimeout: RemoteOperationSupport.interactiveReconnectWaitTimeout
                )
                guard !Task.isCancelled else { return }
                let applied = await MainActor.run { self.applyServerContent(newContent, for: path) }
                guard applied else { return }
                succeeded = true
                refreshLog.info("refresh() read succeeded")
            } catch {
                guard !Task.isCancelled else { return }
                refreshLog.error("refresh() read failed: \(error)")
            }

            guard !Task.isCancelled else { return }
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
            guard !Task.isCancelled else { return }
            refreshLog.info("refresh() done, clearing spinner (succeeded=\(succeeded))")
            await MainActor.run {
                self.isRefreshing = false
            }
        }
    }

    /// Loads a different file in the same window
    func loadFile(at path: String) async throws {
        refreshTask?.cancel()
        refreshTask = nil
        reloadTask?.cancel()
        reloadTask = nil

        // Show the spinner while the sidebar selection loads. Without it a wedged
        // connection left the old document on screen with no feedback, so the
        // window looked hung. Interactive timeouts bound the wait; the spinner
        // always clears.
        isRefreshing = true
        defer { isRefreshing = false }

        let newContent = try await readRemoteDocumentContent(
            fileProvider: fileProvider,
            path: path,
            pingFirst: true,
            interactive: true,
            fullTimeout: RemoteOperationSupport.interactiveFullTimeout,
            reconnectWaitTimeout: RemoteOperationSupport.interactiveReconnectWaitTimeout
        )

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

    func detectGitChanges() async {
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
                    cacheContent(newContent)
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

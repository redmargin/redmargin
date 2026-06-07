import Foundation
import RedmarginCore

// MARK: - On-demand connection model

extension RemoteDocumentState {
    /// Starts the live work a connected remote window needs: App Nap prevention,
    /// the file watcher, git detection, and connection-state observation. This is
    /// the work that used to run unconditionally in `init`; an on-demand window
    /// defers it until its first successful connect.
    func startLiveConnectionWork() async {
        if !didBeginActivity {
            didBeginActivity = true
            await SSHConnectionManager.shared.beginRemoteDocumentActivity()
        }
        async let watcher: Void = setupFileWatcher()
        async let git: Void = detectGitChanges()
        _ = await (watcher, git)
        await startObservingConnectionState()
    }

    /// Connects this window if it is not already connecting/connected.
    ///
    /// Drives the single-flight-per-host `SSHConnectionManager.ensureConnected`,
    /// retrying only transient failures with full-jitter backoff. On success it
    /// starts live work, marks the phase `.connected`, then revalidates the cached
    /// content against the server. Hard-unreachable, refused, and auth failures
    /// are terminal and surface an inline message with Retry.
    func connectIfNeeded(force: Bool = false) async {
        if !force {
            switch connectionPhase {
            case .connecting, .connected:
                return
            case .onDemand, .unavailable:
                break
            }
        }
        guard !isConnecting else { return }
        isConnecting = true
        defer { isConnecting = false }

        connectionPhase = .connecting

        let host = location.host
        do {
            try await RemoteConnectRetry.run {
                _ = try await SSHConnectionManager.shared.ensureConnected(for: host)
            }
        } catch let error as SSHConnectionError {
            applyConnectFailure(error)
            return
        } catch {
            connectionPhase = .unavailable(.serverError)
            return
        }

        await startLiveConnectionWork()
        connectionPhase = .connected
        await revalidateAfterConnect()

        // Let a deferred file tree (folder windows, and file-window sidebars) load
        // now that the connection is live.
        NotificationCenter.default.post(
            name: .remoteWindowDidConnect,
            object: location.storageKey
        )
    }

    /// Maps a terminal connect error to its inline `unavailable` reason.
    private func applyConnectFailure(_ error: SSHConnectionError) {
        connectionPhase = .unavailable(.forConnectError(error))
    }

    /// After connecting, re-read the file and reconcile it against the cached
    /// content. A file that has since been deleted moves the window to
    /// `.unavailable(.fileNotFound)` while keeping its cached content visible.
    private func revalidateAfterConnect() async {
        let path = location.path
        // Folder windows have no document content to revalidate; their tree loads
        // via the did-connect signal instead.
        guard !path.hasSuffix("/") else { return }
        do {
            let serverContent = try await readRemoteDocumentContent(
                fileProvider: fileProvider,
                path: path,
                pingFirst: false
            )
            revalidateWithServerContent(serverContent, for: path)
        } catch let error as RemoteFileError where error.isFileNotFound {
            connectionPhase = .unavailable(.fileNotFound)
        } catch {
            // A transient read failure right after connect is recovered by the
            // file watcher / refresh paths; keep the window connected with content.
            print("[RemoteDocumentState] revalidateAfterConnect read failed: \(error)")
        }
    }
}

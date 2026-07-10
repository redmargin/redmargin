import Foundation

public struct RemoteFileError: LocalizedError {
    public let message: String
    public let code: FileErrorCode?

    public init(message: String, code: FileErrorCode?) {
        self.message = message
        self.code = code
    }

    public var errorDescription: String? { message }

    public var isFileNotFound: Bool {
        code == .fileNotFound
    }
}

public actor RemoteFileProvider: FileProvider {
    private let connection: SSHConnection
    private var watchers: [WatchToken: WatchCallback] = [:]
    private var remoteTokens: [WatchToken: String] = [:] // Local Token -> Remote Token String
    /// Git-repo watch tokens are tracked separately so unwatch routes to the
    /// git unwatch RPC. They previously shared `remoteTokens`, so unwatching a
    /// git repo sent UnwatchFile, which the server resolved against its file
    /// watchers and never matched — leaking the git watcher's inotify FDs.
    private var gitRepoRemoteTokens: [WatchToken: String] = [:]
    private var gitRepoCache: [String: String?] = [:]

    /// Access to connection state changes for UI updates
    public nonisolated var stateChanges: AsyncStream<SSHConnectionState> {
        connection.stateChanges
    }

    /// Get current connection state
    public func getConnectionState() async -> SSHConnectionState {
        await connection.getState()
    }

    /// Returns true if the connection is connected and the SSH process is running
    public func isConnectionAlive() async -> Bool {
        await connection.isAlive()
    }

    /// Seconds since the last successful RPC response
    public func connectionIdleTime() async -> TimeInterval {
        await connection.idleTime()
    }

    /// Quick ping to check if the connection is responsive. A timeout must NOT
    /// tear down the transport: this is the liveness probe on the interactive
    /// path, and on a slow-but-healthy link a >timeout ping would otherwise
    /// force-disconnect a working connection. Report not-alive and let the caller
    /// decide.
    public func ping(timeout: TimeInterval = 3) async -> Bool {
        do {
            let hello = HelloPayload(clientVersion: AppVersion.current, protocolVersion: 1)
            _ = try await connection.send(
                type: RPCMessageType.hello.rawValue, payload: hello,
                timeout: timeout, disconnectOnTimeout: false
            )
            return true
        } catch {
            return false
        }
    }

    /// Force an immediate reconnection attempt
    public func forceReconnect() async {
        await connection.forceReconnect()
    }

    /// Restart the remote helper daemon, then reconnect.
    public func forceRestartRemoteServer() async throws {
        try await connection.forceRestartRemoteServer()
    }

    private struct WatchCallback {
        let path: String
        let callback: () -> Void
    }

    private struct DirectoryWatchCallback {
        let path: String
        let callback: ([String]) -> Void
    }
    private var directoryWatchers: [WatchToken: DirectoryWatchCallback] = [:]
    private var directoryRemoteTokens: [WatchToken: String] = [:]

    /// The push-event listener, cancelled in deinit. `connection`'s event stream
    /// only finishes at connection teardown (the connection is cached per host
    /// for the app's life), so an unowned listener would park forever holding the
    /// connection, leaking one task per document opened. Only init writes it and
    /// only deinit reads it, never concurrently, so nonisolated(unsafe) is safe
    /// and keeps the nonisolated init free of an actor-isolation warning.
    private nonisolated(unsafe) var eventListenerTask: Task<Void, Never>?

    public init(connection: SSHConnection) {
        self.connection = connection

        // Start listening for push events. Take a dedicated subscription rather
        // than iterating `connection.events`: that stream is single-consumer, so
        // when several windows share a host's connection each event would reach
        // only one of them and the intended window would miss its update.
        // Dispatch through weak self so a closed provider stops driving callbacks
        // and the task can be cancelled from deinit.
        let conn = connection
        eventListenerTask = Task { [weak self] in
            let subscription = await conn.addEventSubscriber()
            // Release the subscription however this task ends: cancellation from
            // deinit, provider deallocation, or connection teardown.
            defer { Task { await conn.removeEventSubscriber(subscription.id) } }

            for await eventData in subscription.stream {
                if Task.isCancelled { break }
                guard let self else { break }
                await self.handlePushEvent(eventData)
            }
        }
    }

    deinit {
        eventListenerTask?.cancel()
    }

    public func readFile(at path: String) async throws -> String {
        try await readFile(at: path, timeout: 30)
    }

    public func readFile(at path: String, timeout: TimeInterval) async throws -> String {
        try await readFile(at: path, timeout: timeout, disconnectOnTimeout: true)
    }

    public func readFile(
        at path: String,
        timeout: TimeInterval,
        disconnectOnTimeout: Bool
    ) async throws -> String {
        let payload = ReadFilePayload(path: path)
        let data = try await connection.send(
            type: RPCMessageType.readFile.rawValue,
            payload: payload,
            timeout: timeout,
            disconnectOnTimeout: disconnectOnTimeout
        )
        let response = try JSONDecoder().decode(RPCMessage<ReadFileResponsePayload>.self, from: data)

        if let error = response.payload.error {
            throw RemoteFileError(
                message: error,
                code: response.payload.errorCode.flatMap { FileErrorCode(rawValue: $0) }
            )
        }

        return response.payload.content ?? ""
    }

    public func writeFile(at path: String, content: String) async throws {
        let payload = WriteFilePayload(path: path, content: content)
        let data = try await connection.send(type: RPCMessageType.writeFile.rawValue, payload: payload)
        let response = try JSONDecoder().decode(RPCMessage<WriteFileResponsePayload>.self, from: data)

        if let error = response.payload.error {
            throw NSError(domain: "RemoteFileProvider", code: 2, userInfo: [NSLocalizedDescriptionKey: error])
        }
    }

    public func watchFile(at path: String, onChange: @escaping () -> Void) async -> WatchToken {
        let token = WatchToken()
        watchers[token] = WatchCallback(path: path, callback: onChange)
        await registerRemoteFileWatch(token: token, path: path)
        return token
    }

    /// Register the file watch with the server. Retries on failure because
    /// the open document watcher is the primary mechanism for auto-refresh —
    /// a silent failure here means the user stops getting updates.
    private func registerRemoteFileWatch(token: WatchToken, path: String) async {
        let payload = WatchFilePayload(path: path)
        let attempts = 3
        for attempt in 1...attempts {
            do {
                let data = try await connection.send(
                    type: RPCMessageType.watchFile.rawValue,
                    payload: payload,
                    timeout: 20
                )
                let response = try JSONDecoder().decode(RPCMessage<WatchFileResponsePayload>.self, from: data)
                remoteTokens[token] = response.payload.token
                RemoteLog.info("[RemoteFileProvider] Watching \(path) (attempt \(attempt))")
                return
            } catch {
                RemoteLog.error("[RemoteFileProvider] watchFile \(path) failed (attempt \(attempt)/\(attempts)): \(error)")
                if attempt < attempts {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                }
            }
        }
        RemoteLog.error("[RemoteFileProvider] watchFile \(path) gave up after \(attempts) attempts")
    }

    public func unwatch(_ token: WatchToken) async {
        watchers.removeValue(forKey: token)

        // Git-repo watches must be released via the git unwatch RPC; file watches
        // via the file unwatch RPC. Routing to the wrong one leaves the server's
        // watcher (and its inotify FDs) alive.
        if let gitToken = gitRepoRemoteTokens.removeValue(forKey: token) {
            let payload = UnwatchGitRepoPayload(token: gitToken)
            _ = try? await connection.send(type: RPCMessageType.unwatchGitRepo.rawValue, payload: payload)
            return
        }

        if let remoteToken = remoteTokens.removeValue(forKey: token) {
            let payload = UnwatchFilePayload(token: remoteToken)
            _ = try? await connection.send(type: RPCMessageType.unwatchFile.rawValue, payload: payload)
        }
    }

    public func readAsset(at path: String) async throws -> (data: Data, mimeType: String) {
        try await connection.readAsset(path: path)
    }

    public func detectGitRepo(for path: String) async throws -> String? {
        try await detectGitRepo(for: path, timeout: 20)
    }

    public func detectGitRepo(for path: String, timeout: TimeInterval) async throws -> String? {
        try await detectGitRepo(for: path, timeout: timeout, disconnectOnTimeout: true)
    }

    public func detectGitRepo(
        for path: String,
        timeout: TimeInterval,
        disconnectOnTimeout: Bool
    ) async throws -> String? {
        if let cached = gitRepoCache[path] {
            return cached
        }
        let payload = GitDetectRepoPayload(path: path)
        let data = try await connection.send(
            type: RPCMessageType.gitDetectRepo.rawValue,
            payload: payload,
            timeout: timeout,
            disconnectOnTimeout: disconnectOnTimeout
        )
        let response = try JSONDecoder().decode(
            RPCMessage<GitDetectRepoResponsePayload>.self, from: data)
        gitRepoCache[path] = response.payload.repoRoot
        return response.payload.repoRoot
    }

    public func findMarkdownFiles(in path: String) async throws -> [String] {
        let payload = FindMarkdownFilesPayload(path: path)
        let msgType = RPCMessageType.findMarkdownFiles.rawValue
        let data = try await connection.send(type: msgType, payload: payload, timeout: 30)
        let response = try JSONDecoder().decode(RPCMessage<FindMarkdownFilesResponsePayload>.self, from: data)

        if let error = response.payload.error {
            throw RemoteFileError(message: error, code: nil)
        }

        return response.payload.files ?? []
    }

    public func listDirectory(at path: String) async throws -> [DirectoryEntry] {
        try await listDirectory(at: path, timeout: 30)
    }

    public func listDirectory(at path: String, timeout: TimeInterval) async throws -> [DirectoryEntry] {
        try await listDirectory(at: path, timeout: timeout, disconnectOnTimeout: true)
    }

    public func listDirectory(
        at path: String,
        timeout: TimeInterval,
        disconnectOnTimeout: Bool
    ) async throws -> [DirectoryEntry] {
        let payload = ListDirectoryPayload(path: path)
        let data = try await connection.send(
            type: RPCMessageType.listDirectory.rawValue,
            payload: payload,
            timeout: timeout,
            disconnectOnTimeout: disconnectOnTimeout
        )
        let response = try JSONDecoder().decode(RPCMessage<ListDirectoryResponsePayload>.self, from: data)

        if let error = response.payload.error {
            throw RemoteFileError(message: error, code: nil)
        }

        return response.payload.entries ?? []
    }

    public func gitDiff(for path: String, repoRoot: String) async throws -> GitChangeResult {
        let payload = GitDiffPayload(path: path, repoRoot: repoRoot)
        let data = try await connection.send(type: RPCMessageType.gitDiff.rawValue, payload: payload, timeout: 20)
        let response = try JSONDecoder().decode(RPCMessage<GitDiffResponsePayload>.self, from: data)

        if let error = response.payload.error {
            throw NSError(domain: "RemoteFileProvider", code: 3, userInfo: [NSLocalizedDescriptionKey: error])
        }

        return response.payload.diff ?? .empty
    }

    public func gitStatus(for path: String) async throws -> GitStatusSnapshot {
        let payload = GitStatusPayload(path: path)
        let data = try await connection.send(type: RPCMessageType.gitStatus.rawValue, payload: payload, timeout: 20)
        let response = try JSONDecoder().decode(RPCMessage<GitStatusResponsePayload>.self, from: data)

        if let error = response.payload.error {
            throw NSError(domain: "RemoteFileProvider", code: 4, userInfo: [NSLocalizedDescriptionKey: error])
        }

        return response.payload.snapshot ?? .empty
    }

    public func watchDirectory(at path: String, onChange: @escaping ([String]) -> Void) async -> WatchToken {
        let token = WatchToken()
        directoryWatchers[token] = DirectoryWatchCallback(path: path, callback: onChange)

        let payload = WatchDirectoryPayload(path: path)
        do {
            let data = try await connection.send(type: RPCMessageType.watchDirectory.rawValue, payload: payload)
            let response = try JSONDecoder().decode(
                RPCMessage<WatchDirectoryResponsePayload>.self, from: data)
            directoryRemoteTokens[token] = response.payload.token
        } catch {
            RemoteLog.error("[RemoteFileProvider] Failed to start remote directory watch for \(path): \(error)")
        }

        return token
    }

    public func unwatchDirectory(_ token: WatchToken) async {
        let remoteToken = directoryRemoteTokens.removeValue(forKey: token)
        directoryWatchers.removeValue(forKey: token)

        if let remoteToken = remoteToken {
            let payload = UnwatchDirectoryPayload(token: remoteToken)
            _ = try? await connection.send(type: RPCMessageType.unwatchDirectory.rawValue, payload: payload)
        }
    }

    public func watchGitRepo(at repoRoot: String, onChange: @escaping () -> Void) async -> WatchToken {
        let token = WatchToken()
        watchers[token] = WatchCallback(path: repoRoot, callback: onChange)

        let payload = WatchGitRepoPayload(repoRoot: repoRoot)
        do {
            let data = try await connection.send(type: RPCMessageType.watchGitRepo.rawValue, payload: payload)
            let response = try JSONDecoder().decode(RPCMessage<WatchGitRepoResponsePayload>.self, from: data)
            gitRepoRemoteTokens[token] = response.payload.token
        } catch {
            RemoteLog.error("[RemoteFileProvider] Failed to start remote git watch for \(repoRoot): \(error)")
        }

        return token
    }

    private func handlePushEvent(_ data: Data) {
        RemoteLog.info("[RemoteFileProvider] handlePushEvent called, data size: \(data.count)")
        if let msg = try? JSONDecoder().decode(RPCMessage<FileChangedPayload>.self, from: data),
           msg.type == RPCMessageType.fileChanged.rawValue {
            RemoteLog.info("[RemoteFileProvider] File changed event: \(msg.payload.path)")
            let callbacks = watchers.values.filter { $0.path == msg.payload.path }
            RemoteLog.info("[RemoteFileProvider] Found \(callbacks.count) watchers for path")
            for item in callbacks {
                item.callback()
            }
        } else if let msg = try? JSONDecoder().decode(RPCMessage<DirectoryChangedPayload>.self, from: data),
                  msg.type == RPCMessageType.directoryChanged.rawValue {
            let fileCount = msg.payload.files.count
            RemoteLog.info("[RemoteFileProvider] Directory changed: \(msg.payload.path) (\(fileCount) files)")
            let callbacks = directoryWatchers.values.filter { $0.path == msg.payload.path }
            for item in callbacks {
                item.callback(msg.payload.files)
            }
        } else if let msg = try? JSONDecoder().decode(RPCMessage<GitChangedPayload>.self, from: data),
                  msg.type == RPCMessageType.gitChanged.rawValue {
            RemoteLog.info("[RemoteFileProvider] Git changed event: \(msg.payload.repoRoot)")
            let callbacks = watchers.values.filter { $0.path == msg.payload.repoRoot }
            RemoteLog.info("[RemoteFileProvider] Found \(callbacks.count) watchers for repo")
            for item in callbacks {
                item.callback()
            }
        } else {
            if let text = String(data: data, encoding: .utf8) {
                RemoteLog.info("[RemoteFileProvider] Unknown push event: \(text.prefix(200))")
            }
        }
    }
}

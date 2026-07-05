import Foundation

public enum RemoteOperationSupport {
    public static let pingTimeout: TimeInterval = 3
    public static let probeTimeout: TimeInterval = 5
    public static let fullReadTimeout: TimeInterval = 30
    public static let fullDirectoryTimeout: TimeInterval = 30
    public static let detectGitRepoTimeout: TimeInterval = 20
    public static let reconnectWaitTimeout: TimeInterval = 20

    /// Tighter bounds for operations driven by a direct user gesture (refresh,
    /// opening a file from the sidebar). A wedged connection should fail the
    /// gesture in a bounded time and let the background reconnect heal, not stack
    /// timeouts into a 50-80s stall.
    public static let interactiveFullTimeout: TimeInterval = 15
    public static let interactiveReconnectWaitTimeout: TimeInterval = 8
}

public func waitForRemoteConnection(
    fileProvider: RemoteFileProvider,
    timeout: TimeInterval = RemoteOperationSupport.reconnectWaitTimeout
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        guard !Task.isCancelled else { return false }
        if await fileProvider.getConnectionState() == .connected {
            return true
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
    }
    return false
}

/// Reads a remote document.
///
/// `interactive` marks a user-driven gesture: on that path the deep-fallback
/// server redeploy (kill + scp, tens of seconds) is NOT run inline, because it
/// freezes the UI. Instead a background reconnect is kicked (it self-heals,
/// redeploy included) and the operation fails fast so the caller can show a
/// "reconnecting" state and the user can retry.
public func readRemoteDocumentContent(
    fileProvider: RemoteFileProvider,
    path: String,
    pingFirst: Bool = true,
    interactive: Bool = false,
    probeTimeout: TimeInterval = RemoteOperationSupport.probeTimeout,
    fullTimeout: TimeInterval = RemoteOperationSupport.fullReadTimeout,
    reconnectWaitTimeout: TimeInterval = RemoteOperationSupport.reconnectWaitTimeout
) async throws -> String {
    try await performResponsiveRemoteOperation(
        fileProvider: fileProvider,
        pingFirst: pingFirst,
        interactive: interactive,
        probeTimeout: probeTimeout,
        fullTimeout: fullTimeout,
        reconnectWaitTimeout: reconnectWaitTimeout,
        probeOperation: { timeout, disconnectOnTimeout in
            try await fileProvider.readFile(
                at: path,
                timeout: timeout,
                disconnectOnTimeout: disconnectOnTimeout
            )
        },
        fullOperation: { timeout in
            try await fileProvider.readFile(at: path, timeout: timeout)
        }
    )
}

public func listRemoteDirectoryEntries(
    fileProvider: RemoteFileProvider,
    path: String,
    pingFirst: Bool = true,
    interactive: Bool = false,
    probeTimeout: TimeInterval = RemoteOperationSupport.probeTimeout,
    fullTimeout: TimeInterval = RemoteOperationSupport.fullDirectoryTimeout,
    reconnectWaitTimeout: TimeInterval = RemoteOperationSupport.reconnectWaitTimeout
) async throws -> [DirectoryEntry] {
    try await performResponsiveRemoteOperation(
        fileProvider: fileProvider,
        pingFirst: pingFirst,
        interactive: interactive,
        probeTimeout: probeTimeout,
        fullTimeout: fullTimeout,
        reconnectWaitTimeout: reconnectWaitTimeout,
        probeOperation: { timeout, disconnectOnTimeout in
            try await fileProvider.listDirectory(
                at: path,
                timeout: timeout,
                disconnectOnTimeout: disconnectOnTimeout
            )
        },
        fullOperation: { timeout in
            try await fileProvider.listDirectory(at: path, timeout: timeout)
        }
    )
}

public func detectRemoteGitRepo(
    fileProvider: RemoteFileProvider,
    path: String,
    pingFirst: Bool = true,
    interactive: Bool = false,
    probeTimeout: TimeInterval = RemoteOperationSupport.probeTimeout,
    fullTimeout: TimeInterval = RemoteOperationSupport.detectGitRepoTimeout,
    reconnectWaitTimeout: TimeInterval = RemoteOperationSupport.reconnectWaitTimeout
) async throws -> String? {
    try await performResponsiveRemoteOperation(
        fileProvider: fileProvider,
        pingFirst: pingFirst,
        interactive: interactive,
        probeTimeout: probeTimeout,
        fullTimeout: fullTimeout,
        reconnectWaitTimeout: reconnectWaitTimeout,
        probeOperation: { timeout, disconnectOnTimeout in
            try await fileProvider.detectGitRepo(
                for: path,
                timeout: timeout,
                disconnectOnTimeout: disconnectOnTimeout
            )
        },
        fullOperation: { timeout in
            try await fileProvider.detectGitRepo(for: path, timeout: timeout)
        }
    )
}

private func performResponsiveRemoteOperation<T>(
    fileProvider: RemoteFileProvider,
    pingFirst: Bool,
    interactive: Bool,
    probeTimeout: TimeInterval,
    fullTimeout: TimeInterval,
    reconnectWaitTimeout: TimeInterval,
    probeOperation: (TimeInterval, Bool) async throws -> T,
    fullOperation: (TimeInterval) async throws -> T
) async throws -> T {
    if pingFirst {
        let alive = await fileProvider.ping(timeout: RemoteOperationSupport.pingTimeout)
        if !alive {
            return try await reconnectAndRunRemoteOperation(
                fileProvider: fileProvider,
                interactive: interactive,
                fullTimeout: fullTimeout,
                reconnectWaitTimeout: reconnectWaitTimeout,
                fullOperation: fullOperation
            )
        }
    }

    do {
        return try await probeOperation(probeTimeout, false)
    } catch is CancellationError {
        throw CancellationError()
    } catch let error as SSHConnectionError {
        guard shouldRecoverRemoteOperation(from: error) else {
            throw error
        }

        if case .operationTimeout = error {
            let alive = await fileProvider.ping(timeout: RemoteOperationSupport.pingTimeout)
            if alive {
                return try await fullOperation(fullTimeout)
            }
            return try await recoverRemoteOperation(
                fileProvider: fileProvider,
                interactive: interactive,
                fullTimeout: fullTimeout,
                fullOperation: fullOperation
            )
        }
    } catch {
        throw error
    }

    return try await reconnectAndRunRemoteOperation(
        fileProvider: fileProvider,
        interactive: interactive,
        fullTimeout: fullTimeout,
        reconnectWaitTimeout: reconnectWaitTimeout,
        fullOperation: fullOperation
    )
}

private func reconnectAndRunRemoteOperation<T>(
    fileProvider: RemoteFileProvider,
    interactive: Bool,
    fullTimeout: TimeInterval,
    reconnectWaitTimeout: TimeInterval,
    fullOperation: (TimeInterval) async throws -> T
) async throws -> T {
    await fileProvider.forceReconnect()
    let connected = await waitForRemoteConnection(
        fileProvider: fileProvider,
        timeout: reconnectWaitTimeout
    )
    guard connected else {
        return try await recoverRemoteOperation(
            fileProvider: fileProvider,
            interactive: interactive,
            fullTimeout: fullTimeout,
            fullOperation: fullOperation
        )
    }
    do {
        return try await fullOperation(fullTimeout)
    } catch let error as SSHConnectionError {
        guard shouldRecoverRemoteOperation(from: error) else { throw error }
        return try await recoverRemoteOperation(
            fileProvider: fileProvider,
            interactive: interactive,
            fullTimeout: fullTimeout,
            fullOperation: fullOperation
        )
    }
}

/// Last-resort recovery. Off the interactive path this is a full server redeploy
/// (removeDeployedServer + connect), which is correct but slow. ON the
/// interactive path that redeploy would freeze the UI for tens of seconds, so
/// instead kick the background reconnect (it self-heals, redeploy included) and
/// fail fast; the caller surfaces "reconnecting" and the user retries.
private func recoverRemoteOperation<T>(
    fileProvider: RemoteFileProvider,
    interactive: Bool,
    fullTimeout: TimeInterval,
    fullOperation: (TimeInterval) async throws -> T
) async throws -> T {
    if interactive {
        await fileProvider.forceReconnect()
        throw SSHConnectionError.operationTimeout(operation: "interactive remote operation")
    }
    try await fileProvider.forceRestartRemoteServer()
    return try await fullOperation(fullTimeout)
}

private func shouldRecoverRemoteOperation(from error: SSHConnectionError) -> Bool {
    switch error {
    case .operationTimeout, .unexpectedDisconnect, .serverNotResponding,
         .connectionTimeout, .helperStartupTimeout, .handshakeTimeout:
        return true
    case .sshProcessFailed, .authenticationFailed, .hostUnreachable, .connectionRefused:
        return false
    }
}

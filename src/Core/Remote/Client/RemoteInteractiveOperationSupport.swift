import Foundation

public enum RemoteOperationSupport {
    public static let pingTimeout: TimeInterval = 3
    public static let probeTimeout: TimeInterval = 5
    public static let fullReadTimeout: TimeInterval = 30
    public static let fullDirectoryTimeout: TimeInterval = 30
    public static let detectGitRepoTimeout: TimeInterval = 20
    public static let reconnectWaitTimeout: TimeInterval = 20
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

public func readRemoteDocumentContent(
    fileProvider: RemoteFileProvider,
    path: String,
    pingFirst: Bool = true,
    probeTimeout: TimeInterval = RemoteOperationSupport.probeTimeout,
    fullTimeout: TimeInterval = RemoteOperationSupport.fullReadTimeout,
    reconnectWaitTimeout: TimeInterval = RemoteOperationSupport.reconnectWaitTimeout
) async throws -> String {
    try await performResponsiveRemoteOperation(
        fileProvider: fileProvider,
        pingFirst: pingFirst,
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
    probeTimeout: TimeInterval = RemoteOperationSupport.probeTimeout,
    fullTimeout: TimeInterval = RemoteOperationSupport.fullDirectoryTimeout,
    reconnectWaitTimeout: TimeInterval = RemoteOperationSupport.reconnectWaitTimeout
) async throws -> [DirectoryEntry] {
    try await performResponsiveRemoteOperation(
        fileProvider: fileProvider,
        pingFirst: pingFirst,
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
    probeTimeout: TimeInterval = RemoteOperationSupport.probeTimeout,
    fullTimeout: TimeInterval = RemoteOperationSupport.detectGitRepoTimeout,
    reconnectWaitTimeout: TimeInterval = RemoteOperationSupport.reconnectWaitTimeout
) async throws -> String? {
    try await performResponsiveRemoteOperation(
        fileProvider: fileProvider,
        pingFirst: pingFirst,
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
        }
    } catch {
        throw error
    }

    return try await reconnectAndRunRemoteOperation(
        fileProvider: fileProvider,
        fullTimeout: fullTimeout,
        reconnectWaitTimeout: reconnectWaitTimeout,
        fullOperation: fullOperation
    )
}

private func reconnectAndRunRemoteOperation<T>(
    fileProvider: RemoteFileProvider,
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
        throw SSHConnectionError.unexpectedDisconnect
    }
    return try await fullOperation(fullTimeout)
}

private func shouldRecoverRemoteOperation(from error: SSHConnectionError) -> Bool {
    switch error {
    case .operationTimeout, .unexpectedDisconnect, .serverNotResponding,
         .connectionTimeout, .handshakeTimeout:
        return true
    case .sshProcessFailed, .authenticationFailed, .hostUnreachable, .connectionRefused:
        return false
    }
}

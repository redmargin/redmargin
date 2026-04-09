import Foundation
#if canImport(os)
import os.log
#endif

public actor SSHConnectionManager {
    public static let shared = SSHConnectionManager()

    private var connections: [String: SSHConnection] = [:]

    // App Nap prevention — reference-counted activity token (macOS only)
    private var remoteDocumentCount = 0
    #if os(macOS)
    private var appNapActivity: NSObjectProtocol?
    #endif
    #if canImport(os)
    private let logger = Logger(subsystem: "com.redmargin", category: "SSHConnectionManager")
    #endif

    private init() {}

    /// Call when a remote document opens. Prevents App Nap while any remote document is open.
    public func beginRemoteDocumentActivity() {
        remoteDocumentCount += 1
        #if os(macOS)
        if remoteDocumentCount == 1 {
            appNapActivity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiatedAllowingIdleSystemSleep],
                reason: "Active SSH connections for remote documents"
            )
            #if canImport(os)
            logger.info("App Nap prevention started (remote document opened)")
            #endif
        }
        #endif
    }

    /// Call when a remote document closes. Ends App Nap prevention when the last one closes.
    public func endRemoteDocumentActivity() {
        remoteDocumentCount = max(remoteDocumentCount - 1, 0)
        #if os(macOS)
        if remoteDocumentCount == 0, let activity = appNapActivity {
            ProcessInfo.processInfo.endActivity(activity)
            appNapActivity = nil
            #if canImport(os)
            logger.info("App Nap prevention ended (last remote document closed)")
            #endif
        }
        #endif
    }

    public func connection(for host: String) async throws -> SSHConnection {
        if let existing = connections[host] {
            // Check both state AND process health
            if await existing.isAlive() {
                return existing
            }
            // Connection is stale/disconnected, remove it
            connections.removeValue(forKey: host)
        }

        let connection = SSHConnection(host: host)
        try await connection.connect()
        connections[host] = connection
        return connection
    }

    public func registerConnection(_ connection: SSHConnection, for host: String) {
        connections[host] = connection
    }

    public func disconnectAll() async {
        for connection in connections.values {
            await connection.disconnect()
        }
        connections.removeAll()
    }

    public func disconnect(host: String) async {
        if let connection = connections.removeValue(forKey: host) {
            await connection.disconnect()
        }
    }

    /// Forces all connections to reconnect immediately.
    /// Called on system wake from sleep when TCP connections are likely dead.
    public func forceReconnectAll() async {
        for connection in connections.values {
            await connection.forceReconnect()
        }
    }
}

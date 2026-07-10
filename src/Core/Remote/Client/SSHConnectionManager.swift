import Foundation
#if canImport(os)
import os.log
#endif

public actor SSHConnectionManager {
    public static let shared = SSHConnectionManager()

    private var connections: [String: SSHConnection] = [:]

    /// In-flight connect tasks, one per host, so concurrent `ensureConnected`
    /// callers coalesce onto a single underlying connect attempt.
    private var inFlightConnects: [String: Task<Void, Error>] = [:]

    /// Test instrumentation: counts how many underlying single-flight connect
    /// attempts have been started. Lets a test assert that concurrent callers for
    /// one host coalesce into exactly one connect.
    private(set) var connectStartCount = 0

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
            if await existing.isReusable {
                if await existing.isAlive() {
                    return existing
                }
                // Reusable but not alive — force reconnect on the same object
                await existing.forceReconnect()
                return existing
            }
            // Not reusable (intentionally disconnected) — stop it and replace
            connections.removeValue(forKey: host)
            await existing.disconnect()
        }

        let connection = SSHConnection(host: host)
        try await connection.connect()
        connections[host] = connection
        return connection
    }

    /// Adopts `connection` as the connection for `host`.
    ///
    /// Refuses to displace a different connection that is still usable. Windows
    /// already hold the old object, and overwriting the entry would strand them on
    /// a connection this manager no longer reconnects on wake or shuts down on
    /// quit. A connection that was intentionally disconnected is not usable, so it
    /// is closed and replaced.
    ///
    /// Returns whether `connection` is now the registered one.
    @discardableResult
    public func registerConnection(_ connection: SSHConnection, for host: String) async -> Bool {
        if let existing = connections[host], existing !== connection {
            if await existing.isReusable {
                #if canImport(os)
                logger.error("Refusing to replace the live connection for \(host, privacy: .public)")
                #endif
                return false
            }
            await existing.disconnect()
        }
        connections[host] = connection
        return true
    }

    /// Returns the cached connection for `host`, or creates a fresh, not-yet-connected
    /// one and caches it. Lets a window and its file provider be built before any
    /// connect happens, with all windows on a host sharing one connection object.
    @discardableResult
    public func preregisterConnection(for host: String) -> SSHConnection {
        if let existing = connections[host] {
            return existing
        }
        let connection = SSHConnection(host: host)
        connections[host] = connection
        return connection
    }

    /// Ensures the connection for `host` is live, connecting it if needed.
    ///
    /// Returns immediately if the cached connection is already alive. Otherwise the
    /// (existing or freshly preregistered) connection is connected through a
    /// single-flight per-host task, so concurrent callers await one connect rather
    /// than racing the deploy/handshake. The thrown `SSHConnectionError` is
    /// propagated to every caller and the in-flight entry cleared.
    @discardableResult
    public func ensureConnected(
        for host: String,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws -> SSHConnection {
        if let existing = connections[host], await existing.isAlive() {
            return existing
        }

        let connection = preregisterConnection(for: host)

        if let inFlight = inFlightConnects[host] {
            try await inFlight.value
            return connection
        }

        connectStartCount += 1
        let task = Task<Void, Error> {
            try await connection.connect(onProgress: onProgress)
        }
        inFlightConnects[host] = task
        defer { inFlightConnects[host] = nil }
        try await task.value
        return connection
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

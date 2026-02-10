import Foundation

public actor SSHConnectionManager {
    public static let shared = SSHConnectionManager()

    private var connections: [String: SSHConnection] = [:]

    private init() {}

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

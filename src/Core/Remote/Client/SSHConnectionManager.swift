import Foundation

public actor SSHConnectionManager {
    public static let shared = SSHConnectionManager()
    
    private var connections: [String: SSHConnection] = [:]
    
    private init() {}
    
    public func connection(for host: String) async throws -> SSHConnection {
        if let existing = connections[host] {
            return existing
        }
        
        let connection = SSHConnection(host: host)
        try await connection.connect()
        connections[host] = connection
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
}

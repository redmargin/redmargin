import Foundation

extension Notification.Name {
    public static let sshConnectionReconnected = Notification.Name("RedMargin.sshConnectionReconnected")
}

/// Connection state for SSH sessions
public enum SSHConnectionState: String, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting
}

/// Errors that can occur during SSH connection
public enum SSHConnectionError: Error, LocalizedError, Sendable {
    case connectionTimeout(host: String)
    case handshakeTimeout(host: String)
    case operationTimeout(operation: String)
    case sshProcessFailed(host: String, stderr: String)
    case authenticationFailed(host: String)
    case hostUnreachable(host: String)
    case connectionRefused(host: String)
    case serverNotResponding(host: String)
    case unexpectedDisconnect

    public var errorDescription: String? {
        switch self {
        case .connectionTimeout(let host):
            return "Connection to \(host) timed out. Check that the host is reachable and SSH is running."
        case .handshakeTimeout(let host):
            return "Server on \(host) did not respond. The remote server may not be running or may have crashed."
        case .operationTimeout(let operation):
            return "Operation '\(operation)' timed out. The remote server may be overloaded or unresponsive."
        case .sshProcessFailed(let host, let stderr):
            return "SSH to \(host) failed: \(stderr)"
        case .authenticationFailed(let host):
            return "Authentication to \(host) failed. Check your SSH keys are configured correctly."
        case .hostUnreachable(let host):
            return "Cannot reach \(host). Check your network connection and that the hostname is correct."
        case .connectionRefused(let host):
            return "Connection to \(host) refused. SSH may not be running on the remote host."
        case .serverNotResponding(let host):
            return "Remote server on \(host) is not responding. Try reconnecting."
        case .unexpectedDisconnect:
            return "Connection was unexpectedly closed."
        }
    }
}

/// Thread-safe collector for stderr output
final class StderrCollector: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ newData: Data) {
        lock.lock()
        data.append(newData)
        lock.unlock()
    }

    func getString() -> String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? "Unknown error"
    }
}

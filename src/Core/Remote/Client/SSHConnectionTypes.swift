import Foundation

extension Notification.Name {
    public static let sshConnectionReconnected = Notification.Name("RedMargin.sshConnectionReconnected")

    /// Posted to ask a specific on-demand remote window to connect. The notification
    /// `object` is the target window's `RemoteLocation.storageKey` string.
    public static let remoteWindowConnectRequest = Notification.Name("RedMargin.remoteWindowConnectRequest")

    /// Posted after an on-demand remote window first connects, so its deferred file
    /// tree can load. The `object` is the window's `RemoteLocation.storageKey` string.
    public static let remoteWindowDidConnect = Notification.Name("RedMargin.remoteWindowDidConnect")
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
    case helperStartupTimeout(host: String, stderr: String)
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
            return "SSH connection to \(host) timed out before the remote helper started."
        case .helperStartupTimeout(let host, let stderr):
            let details = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if details.isEmpty {
                return "Redmargin connected to \(host), but the remote helper did not finish starting."
            }
            return "Redmargin connected to \(host), but the remote helper did not finish starting: \(details)"
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

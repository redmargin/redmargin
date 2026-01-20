import Foundation

/// Actor for accumulating data from async callbacks during sync marker detection
actor SyncMarkerAccumulator {
    private var buffer = Data()
    private var foundMarker = false
    private var markerEndIndex: Data.Index?
    private static let syncMarkerData = "REDMARGIN_SYNC_7f3d9a\n".data(using: .utf8)!

    func append(_ data: Data, marker: Data) {
        buffer.append(data)
        if let range = buffer.range(of: marker) {
            foundMarker = true
            markerEndIndex = range.upperBound
        }
    }

    func getResult() -> (found: Bool, discarded: Data, remaining: Data) {
        guard foundMarker, let endIndex = markerEndIndex else {
            return (false, Data(), Data())
        }
        let startIndex = buffer.range(of: Self.syncMarkerData)?.lowerBound ?? buffer.startIndex
        return (true, buffer.prefix(upTo: startIndex), buffer.suffix(from: endIndex))
    }

    func getBuffer() -> Data { buffer }
}

/// Parses SSH stderr output into appropriate connection errors
func parseSSHStderr(_ stderr: String, host: String) -> SSHConnectionError {
    let lower = stderr.lowercased()
    if lower.contains("permission denied") || lower.contains("publickey") {
        return .authenticationFailed(host: host)
    } else if lower.contains("connection refused") {
        return .connectionRefused(host: host)
    } else if lower.contains("no route to host") || lower.contains("network is unreachable") {
        return .hostUnreachable(host: host)
    } else if lower.contains("timed out") || lower.contains("timeout") {
        return .connectionTimeout(host: host)
    } else {
        return .sshProcessFailed(host: host, stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

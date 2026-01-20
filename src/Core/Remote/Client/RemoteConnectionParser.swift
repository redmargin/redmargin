import Foundation

/// Parses SSH connection strings in the format `user@host:/path` or `host:/path`
public enum RemoteConnectionParser {
    public struct ParsedConnection: Equatable {
        public let host: String
        public let path: String

        public init(host: String, path: String) {
            self.host = host
            self.path = path
        }
    }

    /// Parse a connection string into host and path components.
    /// - Parameter connectionString: String in format "user@host:/path" or "host:/path"
    /// - Returns: Parsed connection if valid, nil otherwise
    public static func parse(_ connectionString: String) -> ParsedConnection? {
        let trimmed = connectionString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Format: user@host:/path or host:/path
        // Find ":/" which is the separator between host and absolute path
        // This handles paths that contain colons (e.g., host:/path/with:colons/file.md)
        guard let separatorRange = trimmed.range(of: ":/") else {
            return nil
        }

        let host = String(trimmed[..<separatorRange.lowerBound])
        // Path includes the leading / (separatorRange.upperBound is after the /)
        let path = "/" + String(trimmed[separatorRange.upperBound...])

        guard !host.isEmpty else {
            return nil
        }

        // Basic host validation - no spaces unless part of user@host format
        guard host.contains("@") || !host.contains(" ") else {
            return nil
        }

        return ParsedConnection(host: host, path: path)
    }
}

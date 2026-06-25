import Foundation

/// Represents a remote file location (host + path)
public struct RemoteLocation: Hashable, Codable, Sendable {
    public let host: String
    public let path: String

    public init(host: String, path: String) {
        self.host = host
        self.path = path
    }

    public var displayString: String {
        "\(host):\(path)"
    }

    public var displayTitle: String {
        displayString
    }

    public var storageKey: String {
        "\(host):\(path)"
    }
}

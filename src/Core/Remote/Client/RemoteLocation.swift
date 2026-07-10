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

    /// Folder locations carry a trailing separator; file locations never do.
    /// This is how a folder window's location is told from a document window's,
    /// and unlike "the content is empty" it stays true for an empty file.
    public var isFolder: Bool {
        path.hasSuffix("/")
    }
}

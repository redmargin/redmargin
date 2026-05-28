import Foundation

/// A launch request delivered through Redmargin's private URL scheme.
///
/// Example:
/// redmargin://open?host=dev-vm&path=/home/marco/file.md&kind=file
public struct RedmarginLaunchRequest: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case file
        case folder
        case auto
    }

    public let host: String
    public let path: String
    public let kind: Kind

    public init(host: String, path: String, kind: Kind = .auto) {
        self.host = host
        self.path = path
        self.kind = kind
    }

    public static func parse(_ url: URL) -> RedmarginLaunchRequest? {
        guard url.scheme?.lowercased() == "redmargin",
              url.host?.lowercased() == "open",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }

        var query: [String: String] = [:]
        for item in components.queryItems ?? [] where query[item.name] == nil {
            query[item.name] = item.value
        }

        guard let host = query["host"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              let path = query["path"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty,
              path.hasPrefix("/")
        else {
            return nil
        }

        let kind = query["kind"].flatMap { Kind(rawValue: $0.lowercased()) } ?? .auto
        return RedmarginLaunchRequest(host: host, path: path, kind: kind)
    }

    public var url: URL? {
        var components = URLComponents()
        components.scheme = "redmargin"
        components.host = "open"
        components.queryItems = [
            URLQueryItem(name: "host", value: host),
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "kind", value: kind.rawValue)
        ]
        return components.url
    }
}

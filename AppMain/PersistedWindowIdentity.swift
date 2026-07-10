import Foundation
import RedmarginCore

/// How a window names itself in `UserDefaults` between launches.
///
/// The original format joined the fields with colons (`remote:host:path`) and
/// parsed at the first one. An IPv6 host contains colons of its own, so it came
/// back truncated with the remainder glued onto the front of the path, and that
/// window could never be matched on restore. Identities are stored as JSON now,
/// where a colon inside a field is just a character.
enum PersistedWindowIdentity: Codable, Equatable {
    case local(path: String)
    case folder(path: String)
    case remote(RemoteLocation)

    /// The stored representation.
    var encoded: String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Reads either the current JSON form or an identity written by an older build.
    static func decode(_ raw: String) -> PersistedWindowIdentity? {
        if let data = raw.data(using: .utf8),
           let identity = try? JSONDecoder().decode(PersistedWindowIdentity.self, from: data) {
            return identity
        }
        return legacy(raw)
    }

    /// Values written before identities became JSON. An IPv6 remote window was
    /// already unrestorable in this form, so this reproduces the old parse rather
    /// than trying to recover one.
    private static func legacy(_ raw: String) -> PersistedWindowIdentity? {
        if raw.hasPrefix("remote:") {
            let rest = String(raw.dropFirst("remote:".count))
            guard let separator = rest.firstIndex(of: ":") else { return nil }
            let host = String(rest[rest.startIndex..<separator])
            let path = String(rest[rest.index(after: separator)...])
            return .remote(RemoteLocation(host: host, path: path))
        }
        if raw.hasPrefix("folder:") {
            return .folder(path: String(raw.dropFirst("folder:".count)))
        }
        guard !raw.isEmpty else { return nil }
        return .local(path: raw)
    }

    /// The remote location this identity names, if it names one.
    var remoteLocation: RemoteLocation? {
        if case .remote(let location) = self { return location }
        return nil
    }
}

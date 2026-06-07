import Foundation
import RedmarginCore

/// Pure helper that rebuilds the front-to-back placement of restored remote
/// windows and identifies the single window that should be made key.
///
/// Keeping this free of AppKit lets the ordering be unit-tested directly: given a
/// saved back-to-front z-order and the saved frontmost location, it returns the
/// back-to-front placement sequence (so the caller can `orderFront` the first and
/// `order(.above:)` each subsequent window) and the one location to make key.
enum RemoteRestoreOrdering {
    struct Plan: Equatable {
        /// Locations to place, back-to-front.
        let placementOrder: [RemoteLocation]
        /// The single window to make key, or nil if there are none.
        let keyLocation: RemoteLocation?
    }

    /// - Parameters:
    ///   - locations: The remote locations that will be restored (windows exist).
    ///   - savedOrderKeys: Saved back-to-front order as `RemoteLocation.storageKey`
    ///     strings. Empty when no order was persisted.
    ///   - frontmostKey: The saved frontmost location's `storageKey`, or nil when
    ///     the frontmost window was not a remote window (or none was recorded).
    static func plan(
        locations: [RemoteLocation],
        savedOrderKeys: [String],
        frontmostKey: String?
    ) -> Plan {
        let byKey = Dictionary(
            locations.map { ($0.storageKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Placement: saved back-to-front order first (filtered to locations we have),
        // then any remaining locations in their given array order.
        var placement: [RemoteLocation] = []
        var seen = Set<String>()
        for key in savedOrderKeys {
            guard let location = byKey[key], !seen.contains(key) else { continue }
            placement.append(location)
            seen.insert(key)
        }
        for location in locations where !seen.contains(location.storageKey) {
            placement.append(location)
            seen.insert(location.storageKey)
        }

        // Key window: the saved frontmost if it is among the placed windows,
        // otherwise the last-placed (frontmost) window.
        let keyLocation: RemoteLocation?
        if let frontmostKey, let location = byKey[frontmostKey], seen.contains(frontmostKey) {
            keyLocation = location
        } else {
            keyLocation = placement.last
        }

        return Plan(placementOrder: placement, keyLocation: keyLocation)
    }

    /// Strips the `remote:` prefix from a persisted window token (`remote:host:path`)
    /// to recover the `RemoteLocation.storageKey` (`host:path`). Returns nil for
    /// non-remote tokens.
    static func storageKey(fromWindowToken token: String) -> String? {
        guard token.hasPrefix("remote:") else { return nil }
        return String(token.dropFirst("remote:".count))
    }
}

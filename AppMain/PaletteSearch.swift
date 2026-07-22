import Foundation
import RedmarginCore

/// Whitespace-tokenized palette search. Every token must match at least one
/// field of an item; matches are scored so host and title hits outrank
/// incidental path substrings.
struct PaletteSearchQuery {
    let tokens: [String]

    init(_ raw: String) {
        tokens = raw.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    var isEmpty: Bool { tokens.isEmpty }

    /// Total score for a workspace item, or nil when any token fails to match.
    func score(_ item: RecentWorkspaceItem) -> Int? {
        guard !isEmpty else { return 0 }
        let fields = PaletteSearchFields(item)
        var total = 0
        for token in tokens {
            guard let tokenScore = fields.score(token: token) else { return nil }
            total += tokenScore
        }
        return total
    }

    func matches(commandTitle: String) -> Bool {
        let title = commandTitle.lowercased()
        return tokens.allSatisfy { title.contains($0) }
    }
}

private struct PaletteSearchFields {
    let title: String
    let host: String?
    let segments: [String]
    let haystacks: [String]

    init(_ item: RecentWorkspaceItem) {
        title = item.displayTitle.lowercased()
        switch item.location {
        case .local(let url):
            host = nil
            segments = url.pathComponents.map { $0.lowercased() }
            haystacks = [url.path.lowercased(), item.locationText.lowercased()]
        case .remote(let location):
            host = location.host.lowercased()
            segments = location.path.split(separator: "/").map { $0.lowercased() }
            haystacks = [item.locationText.lowercased()]
        }
    }

    func score(token: String) -> Int? {
        if let host {
            if host == token { return 100 }
            if host.hasPrefix(token) { return 80 }
            if host.contains(token) { return 70 }
        }
        if title.hasPrefix(token) { return 60 }
        if title.contains(token) { return 40 }
        if segments.contains(where: { $0.hasPrefix(token) }) { return 30 }
        if haystacks.contains(where: { $0.contains(token) }) { return 15 }
        return nil
    }
}

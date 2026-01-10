import Foundation

/// Result of parsing git diff output for a file
struct GitChangeResult: Equatable {
    /// Line ranges that have been changed (added or modified), 1-indexed
    let changedRanges: [ClosedRange<Int>]

    /// Line numbers where deletions occurred (anchor points), 1-indexed
    /// The anchor is the line number after the deletion point
    let deletedAnchors: [Int]

    /// True if the file is not tracked by git
    let isUntracked: Bool

    /// Creates an empty result (for clean files)
    static let empty = GitChangeResult(changedRanges: [], deletedAnchors: [], isUntracked: false)

    /// Creates a result for an untracked file where all lines are new
    static func untracked(lineCount: Int) -> GitChangeResult {
        let range = lineCount > 0 ? [1...lineCount] : []
        return GitChangeResult(changedRanges: range, deletedAnchors: [], isUntracked: true)
    }
}

extension GitChangeResult: Encodable {
    enum CodingKeys: String, CodingKey {
        case changedRanges
        case deletedAnchors
        case isUntracked
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        // Encode ranges as arrays of [start, end] for JavaScript consumption
        let rangeArrays = changedRanges.map { [$0.lowerBound, $0.upperBound] }
        try container.encode(rangeArrays, forKey: .changedRanges)
        try container.encode(deletedAnchors, forKey: .deletedAnchors)
        try container.encode(isUntracked, forKey: .isUntracked)
    }
}

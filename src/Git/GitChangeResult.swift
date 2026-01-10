import Foundation

/// Result of parsing git diff output for a file
public struct GitChangeResult: Equatable {
    /// Line ranges that were added (new lines, not replacing existing), 1-indexed
    public let addedRanges: [ClosedRange<Int>]

    /// Line ranges that were modified (replacing existing lines), 1-indexed
    public let modifiedRanges: [ClosedRange<Int>]

    /// Line numbers where deletions occurred (anchor points), 1-indexed
    /// The anchor is the line number after the deletion point
    public let deletedAnchors: [Int]

    /// Creates an empty result (for clean files)
    public static let empty = GitChangeResult(addedRanges: [], modifiedRanges: [], deletedAnchors: [])

    /// Creates a result for an untracked file where all lines are new
    public static func untracked(lineCount: Int) -> GitChangeResult {
        let range = lineCount > 0 ? [1...lineCount] : []
        return GitChangeResult(addedRanges: range, modifiedRanges: [], deletedAnchors: [])
    }

    public init(addedRanges: [ClosedRange<Int>], modifiedRanges: [ClosedRange<Int>], deletedAnchors: [Int]) {
        self.addedRanges = addedRanges
        self.modifiedRanges = modifiedRanges
        self.deletedAnchors = deletedAnchors
    }
}

extension GitChangeResult: Encodable {
    enum CodingKeys: String, CodingKey {
        case addedRanges
        case modifiedRanges
        case deletedAnchors
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        // Encode ranges as arrays of [start, end] for JavaScript consumption
        let addedArrays = addedRanges.map { [$0.lowerBound, $0.upperBound] }
        let modifiedArrays = modifiedRanges.map { [$0.lowerBound, $0.upperBound] }
        try container.encode(addedArrays, forKey: .addedRanges)
        try container.encode(modifiedArrays, forKey: .modifiedRanges)
        try container.encode(deletedAnchors, forKey: .deletedAnchors)
    }
}

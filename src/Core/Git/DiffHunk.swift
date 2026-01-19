import Foundation

/// Represents a parsed hunk header from a unified diff
struct DiffHunk: Equatable {
    /// Starting line number in the old file (0 means addition at start)
    let oldStart: Int
    /// Number of lines affected in old file (0 means pure addition)
    let oldCount: Int
    /// Starting line number in the new file
    let newStart: Int
    /// Number of lines affected in new file (0 means pure deletion)
    let newCount: Int

    /// Parses a hunk header string into a DiffHunk
    /// - Parameter hunkHeader: String in format `@@ -oldStart,oldCount +newStart,newCount @@`
    ///   Count can be omitted when it equals 1 (e.g., `@@ -5 +7 @@` means both counts are 1)
    /// - Returns: Parsed DiffHunk, or nil if the string is not a valid hunk header
    static func parse(hunkHeader: String) -> DiffHunk? {
        // Pattern: @@ -oldStart[,oldCount] +newStart[,newCount] @@
        // When count is omitted, it defaults to 1
        let pattern = #"^@@\s+-(\d+)(?:,(\d+))?\s+\+(\d+)(?:,(\d+))?\s+@@"#

        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: hunkHeader,
                range: NSRange(hunkHeader.startIndex..., in: hunkHeader)
              ) else {
            return nil
        }

        func extractInt(at index: Int, default defaultValue: Int = 1) -> Int {
            guard let range = Range(match.range(at: index), in: hunkHeader) else {
                return defaultValue
            }
            return Int(hunkHeader[range]) ?? defaultValue
        }

        let oldStart = extractInt(at: 1, default: 0)
        let oldCount = extractInt(at: 2, default: 1)
        let newStart = extractInt(at: 3, default: 0)
        let newCount = extractInt(at: 4, default: 1)

        return DiffHunk(
            oldStart: oldStart,
            oldCount: oldCount,
            newStart: newStart,
            newCount: newCount
        )
    }
}

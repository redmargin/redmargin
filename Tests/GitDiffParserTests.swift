import XCTest
@testable import RedmarginLib

final class GitDiffParserTests: XCTestCase {

    // MARK: - DiffHunk Parsing Tests

    func testParseSimpleHunk() {
        let hunk = DiffHunk.parse(hunkHeader: "@@ -10,5 +12,3 @@")

        XCTAssertNotNil(hunk)
        XCTAssertEqual(hunk?.oldStart, 10)
        XCTAssertEqual(hunk?.oldCount, 5)
        XCTAssertEqual(hunk?.newStart, 12)
        XCTAssertEqual(hunk?.newCount, 3)
    }

    func testParseHunkOmittedOldCount() {
        // When count is omitted, it defaults to 1
        let hunk = DiffHunk.parse(hunkHeader: "@@ -10 +12,3 @@")

        XCTAssertNotNil(hunk)
        XCTAssertEqual(hunk?.oldStart, 10)
        XCTAssertEqual(hunk?.oldCount, 1)
        XCTAssertEqual(hunk?.newStart, 12)
        XCTAssertEqual(hunk?.newCount, 3)
    }

    func testParseHunkOmittedNewCount() {
        let hunk = DiffHunk.parse(hunkHeader: "@@ -10,5 +12 @@")

        XCTAssertNotNil(hunk)
        XCTAssertEqual(hunk?.oldStart, 10)
        XCTAssertEqual(hunk?.oldCount, 5)
        XCTAssertEqual(hunk?.newStart, 12)
        XCTAssertEqual(hunk?.newCount, 1)
    }

    func testParseHunkBothOmitted() {
        let hunk = DiffHunk.parse(hunkHeader: "@@ -10 +12 @@")

        XCTAssertNotNil(hunk)
        XCTAssertEqual(hunk?.oldStart, 10)
        XCTAssertEqual(hunk?.oldCount, 1)
        XCTAssertEqual(hunk?.newStart, 12)
        XCTAssertEqual(hunk?.newCount, 1)
    }

    func testParseHunkAtStart() {
        // Addition at start of file: oldStart=0, oldCount=0
        let hunk = DiffHunk.parse(hunkHeader: "@@ -0,0 +1,5 @@")

        XCTAssertNotNil(hunk)
        XCTAssertEqual(hunk?.oldStart, 0)
        XCTAssertEqual(hunk?.oldCount, 0)
        XCTAssertEqual(hunk?.newStart, 1)
        XCTAssertEqual(hunk?.newCount, 5)
    }

    func testParseInvalidHunk() {
        XCTAssertNil(DiffHunk.parse(hunkHeader: "not a hunk"))
        XCTAssertNil(DiffHunk.parse(hunkHeader: ""))
        XCTAssertNil(DiffHunk.parse(hunkHeader: "@@ invalid @@"))
        XCTAssertNil(DiffHunk.parse(hunkHeader: "--- a/file.txt"))
    }

    func testParseHunkWithTrailingContext() {
        // Real hunks often have trailing context after @@
        let hunk = DiffHunk.parse(hunkHeader: "@@ -10,5 +12,3 @@ func example() {")

        XCTAssertNotNil(hunk)
        XCTAssertEqual(hunk?.oldStart, 10)
        XCTAssertEqual(hunk?.oldCount, 5)
        XCTAssertEqual(hunk?.newStart, 12)
        XCTAssertEqual(hunk?.newCount, 3)
    }

    func testParseHunkPureDeletion() {
        // Pure deletion: newCount=0
        let hunk = DiffHunk.parse(hunkHeader: "@@ -5,3 +4,0 @@")

        XCTAssertNotNil(hunk)
        XCTAssertEqual(hunk?.oldStart, 5)
        XCTAssertEqual(hunk?.oldCount, 3)
        XCTAssertEqual(hunk?.newStart, 4)
        XCTAssertEqual(hunk?.newCount, 0)
    }

    // MARK: - Fixture Loading Tests

    func testLoadAdditionFixture() throws {
        let content = try FixtureLoader.load("diff-samples/addition.diff")
        XCTAssertTrue(content.contains("@@ -0,0 +1,3 @@"))
    }

    func testLoadDeletionFixture() throws {
        let content = try FixtureLoader.load("diff-samples/deletion.diff")
        XCTAssertTrue(content.contains("@@ -5,3 +4,0 @@"))
    }

    func testLoadModificationFixture() throws {
        let content = try FixtureLoader.load("diff-samples/modification.diff")
        XCTAssertTrue(content.contains("@@ -10,2 +10,2 @@"))
    }

    func testLoadMultipleHunksFixture() throws {
        let content = try FixtureLoader.load("diff-samples/multiple-hunks.diff")
        // Should contain multiple @@ markers
        let hunkCount = content.components(separatedBy: "@@").count - 1
        XCTAssertGreaterThan(hunkCount, 2, "Should have multiple hunks")
    }

    func testLoadEmptyFixture() throws {
        let content = try FixtureLoader.load("diff-samples/empty.diff")
        XCTAssertTrue(content.isEmpty)
    }

    func testLoadBinaryFixture() throws {
        let content = try FixtureLoader.load("diff-samples/binary.diff")
        XCTAssertTrue(content.contains("Binary files"))
    }

    // MARK: - Diff Output Parsing Tests (using fixtures)

    func testParseDiffOutputAddition() throws {
        let content = try FixtureLoader.load("diff-samples/addition.diff")
        let result = GitDiffParser.parseDiffOutput(content)

        XCTAssertEqual(result.changedRanges.count, 1)
        XCTAssertEqual(result.changedRanges.first, 1...3)
        XCTAssertTrue(result.deletedAnchors.isEmpty)
        XCTAssertFalse(result.isUntracked)
    }

    func testParseDiffOutputDeletion() throws {
        let content = try FixtureLoader.load("diff-samples/deletion.diff")
        let result = GitDiffParser.parseDiffOutput(content)

        XCTAssertTrue(result.changedRanges.isEmpty)
        XCTAssertEqual(result.deletedAnchors, [4])
        XCTAssertFalse(result.isUntracked)
    }

    func testParseDiffOutputModification() throws {
        let content = try FixtureLoader.load("diff-samples/modification.diff")
        let result = GitDiffParser.parseDiffOutput(content)

        XCTAssertEqual(result.changedRanges.count, 1)
        XCTAssertEqual(result.changedRanges.first, 10...11)
        XCTAssertTrue(result.deletedAnchors.isEmpty)
    }

    func testParseDiffOutputMultipleHunks() throws {
        let content = try FixtureLoader.load("diff-samples/multiple-hunks.diff")
        let result = GitDiffParser.parseDiffOutput(content)

        // 4 hunks: modification at line 3, addition at 10-11, deletion at 22, modification at 29-32
        XCTAssertEqual(result.changedRanges.count, 3)
        XCTAssertTrue(result.changedRanges.contains(3...3))
        XCTAssertTrue(result.changedRanges.contains(10...11))
        XCTAssertTrue(result.changedRanges.contains(29...32))

        XCTAssertEqual(result.deletedAnchors, [22])
    }

    func testParseDiffOutputEmpty() throws {
        let content = try FixtureLoader.load("diff-samples/empty.diff")
        let result = GitDiffParser.parseDiffOutput(content)

        XCTAssertTrue(result.changedRanges.isEmpty)
        XCTAssertTrue(result.deletedAnchors.isEmpty)
    }

    func testParseDiffOutputBinary() throws {
        let content = try FixtureLoader.load("diff-samples/binary.diff")
        // Binary file detection happens in parseChanges, not parseDiffOutput
        // parseDiffOutput just won't find any @@ markers in binary diff
        let result = GitDiffParser.parseDiffOutput(content)

        XCTAssertTrue(result.changedRanges.isEmpty)
        XCTAssertTrue(result.deletedAnchors.isEmpty)
    }

    // MARK: - GitChangeResult Tests

    func testGitChangeResultEmpty() {
        let result = GitChangeResult.empty

        XCTAssertTrue(result.changedRanges.isEmpty)
        XCTAssertTrue(result.deletedAnchors.isEmpty)
        XCTAssertFalse(result.isUntracked)
    }

    func testGitChangeResultUntracked() {
        let result = GitChangeResult.untracked(lineCount: 10)

        XCTAssertEqual(result.changedRanges.count, 1)
        XCTAssertEqual(result.changedRanges.first, 1...10)
        XCTAssertTrue(result.deletedAnchors.isEmpty)
        XCTAssertTrue(result.isUntracked)
    }

    func testGitChangeResultUntrackedEmptyFile() {
        let result = GitChangeResult.untracked(lineCount: 0)

        XCTAssertTrue(result.changedRanges.isEmpty)
        XCTAssertTrue(result.isUntracked)
    }

    func testGitChangeResultEncodesToJSON() throws {
        let result = GitChangeResult(
            changedRanges: [1...3, 10...15],
            deletedAnchors: [5, 20],
            isUntracked: false
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(result)
        let json = String(data: data, encoding: .utf8)!

        // Ranges should be encoded as arrays
        XCTAssertTrue(json.contains("[[1,3],[10,15]]"))
        XCTAssertTrue(json.contains("[5,20]"))
        XCTAssertTrue(json.contains("\"isUntracked\":false"))
    }
}

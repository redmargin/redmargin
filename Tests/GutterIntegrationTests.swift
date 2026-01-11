import XCTest
@testable import RedmarginLib

final class GutterIntegrationTests: XCTestCase {
    var gitHelper: GitTestHelper!

    override func setUp() {
        super.setUp()
        gitHelper = GitTestHelper()
        try? gitHelper.setUp()
    }

    override func tearDown() {
        gitHelper.tearDown()
        super.tearDown()
    }

    // MARK: - Spec Tests

    func testGutterAppearsForChangedFile() async throws {
        // Create repo with base file
        let repoURL = try gitHelper.createRepo(named: "gutter-test")
        let fileURL = try gitHelper.createFile(
            named: "test.md",
            content: "Line 1\nLine 2\nLine 3\nLine 4\nLine 5\n",
            in: repoURL
        )
        try gitHelper.commit(message: "Initial commit", in: repoURL)

        // Modify lines 2-3
        try "Line 1\nModified 2\nModified 3\nLine 4\nLine 5\n".write(to: fileURL, atomically: true, encoding: .utf8)

        // Get changes
        let repoRoot = try await GitRepoDetector.detectRepoRoot(forFile: fileURL)
        XCTAssertNotNil(repoRoot)

        let changes = try await GitDiffParser.parseChanges(forFile: fileURL, repoRoot: repoRoot!)

        // Should have modified ranges for lines 2-3
        XCTAssertFalse(changes.modifiedRanges.isEmpty, "Should detect modified lines")
        let hasLine2 = changes.modifiedRanges.contains { $0.contains(2) }
        let hasLine3 = changes.modifiedRanges.contains { $0.contains(3) }
        XCTAssertTrue(hasLine2, "Should include line 2 in modified ranges")
        XCTAssertTrue(hasLine3, "Should include line 3 in modified ranges")
    }

    func testGutterEmptyForCleanFile() async throws {
        // Create repo with file
        let repoURL = try gitHelper.createRepo(named: "clean-test")
        let fileURL = try gitHelper.createFile(
            named: "clean.md",
            content: "Unchanged content\n",
            in: repoURL
        )
        try gitHelper.commit(message: "Initial commit", in: repoURL)

        // Don't modify - file is clean
        let repoRoot = try await GitRepoDetector.detectRepoRoot(forFile: fileURL)
        XCTAssertNotNil(repoRoot)

        let changes = try await GitDiffParser.parseChanges(forFile: fileURL, repoRoot: repoRoot!)

        // Should have no changes
        XCTAssertTrue(changes.addedRanges.isEmpty, "Clean file should have no added ranges")
        XCTAssertTrue(changes.modifiedRanges.isEmpty, "Clean file should have no modified ranges")
        XCTAssertTrue(changes.deletedAnchors.isEmpty, "Clean file should have no deleted anchors")
    }

    func testGutterEmptyForNonRepoFile() async throws {
        // Create file outside any git repo
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("non-repo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("orphan.md")
        try "Orphan file\n".write(to: fileURL, atomically: true, encoding: .utf8)

        // Should not detect repo
        let repoRoot = try await GitRepoDetector.detectRepoRoot(forFile: fileURL)
        XCTAssertNil(repoRoot, "File outside repo should have nil repo root")

        // No changes to report since no repo
    }

    // MARK: - Existing Tests

    func testGitChangesForModifiedFile() async throws {
        // Test with the actual README.md which has uncommitted changes
        let fileURL = URL(fileURLWithPath: "/Users/marco/dev/redmargin/README.md")

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw XCTSkip("README.md not found")
        }

        // Detect repo
        let repoRoot = try await GitRepoDetector.detectRepoRoot(forFile: fileURL)
        XCTAssertNotNil(repoRoot, "Should detect repo root")

        // Get changes
        let changes = try await GitDiffParser.parseChanges(forFile: fileURL, repoRoot: repoRoot!)

        print("Added: \(changes.addedRanges.count), Modified: \(changes.modifiedRanges.count), " +
              "Deleted: \(changes.deletedAnchors.count)")
        print("Added ranges: \(changes.addedRanges)")
        print("Modified ranges: \(changes.modifiedRanges)")
        print("Deleted anchors: \(changes.deletedAnchors)")

        // Encode to JSON (like we do for JS)
        let encoder = JSONEncoder()
        let data = try encoder.encode(changes)
        let json = String(data: data, encoding: .utf8) ?? ""
        print("JSON for JS: \(json)")

        // Parse as dictionary to verify structure
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("Failed to parse JSON as dictionary")
            return
        }
        XCTAssertNotNil(dict["addedRanges"], "Should have addedRanges key")
        XCTAssertNotNil(dict["modifiedRanges"], "Should have modifiedRanges key")
        XCTAssertNotNil(dict["deletedAnchors"], "Should have deletedAnchors key")
    }

    func testGitChangeResultEncodesToCorrectFormat() throws {
        // Test that GitChangeResult encodes to the format JS expects
        let changes = GitChangeResult(
            addedRanges: [5...10],
            modifiedRanges: [15...20],
            deletedAnchors: [12]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(changes)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("Failed to parse JSON as dictionary")
            return
        }

        // Check structure
        guard let added = dict["addedRanges"] as? [[Int]] else {
            XCTFail("addedRanges not in expected format")
            return
        }
        XCTAssertEqual(added.count, 1)
        XCTAssertEqual(added[0], [5, 10])

        guard let modified = dict["modifiedRanges"] as? [[Int]] else {
            XCTFail("modifiedRanges not in expected format")
            return
        }
        XCTAssertEqual(modified.count, 1)
        XCTAssertEqual(modified[0], [15, 20])

        guard let anchors = dict["deletedAnchors"] as? [Int] else {
            XCTFail("deletedAnchors not in expected format")
            return
        }
        XCTAssertEqual(anchors, [12])
    }
}

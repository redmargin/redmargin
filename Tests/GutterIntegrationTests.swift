import XCTest
@testable import RedmarginLib

final class GutterIntegrationTests: XCTestCase {

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

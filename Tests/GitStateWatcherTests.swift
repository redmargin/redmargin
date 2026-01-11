import XCTest
import Foundation

/// Tests for git state watching behavior
/// Verifies that HEAD and branch ref changes are detected
final class GitStateWatcherTests: XCTestCase {

    var tempDir: URL!
    var gitDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitStateWatcherTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Create a fake .git directory structure
        gitDir = tempDir.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)

        let refsDir = gitDir.appendingPathComponent("refs/heads")
        try FileManager.default.createDirectory(at: refsDir, withIntermediateDirectories: true)

        // Create HEAD pointing to main branch
        let headFile = gitDir.appendingPathComponent("HEAD")
        try "ref: refs/heads/main\n".write(to: headFile, atomically: true, encoding: .utf8)

        // Create main branch ref
        let mainRef = refsDir.appendingPathComponent("main")
        try "abc123def456\n".write(to: mainRef, atomically: true, encoding: .utf8)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testWatcherDetectsHEADChange() async throws {
        // Tests branch switch detection (git checkout)
        let expectation = XCTestExpectation(description: "HEAD change detected")

        let headFile = gitDir.appendingPathComponent("HEAD")
        let fileDesc = open(headFile.path, O_EVTONLY)
        XCTAssertGreaterThanOrEqual(fileDesc, 0, "Failed to open HEAD file")

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDesc,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )

        source.setEventHandler {
            expectation.fulfill()
        }

        source.setCancelHandler {
            close(fileDesc)
        }

        source.resume()

        // Simulate branch switch by changing HEAD
        try "ref: refs/heads/feature\n".write(to: headFile, atomically: true, encoding: .utf8)

        await fulfillment(of: [expectation], timeout: 2.0)
        source.cancel()
    }

    func testWatcherDetectsBranchRefChange() async throws {
        // Tests commit detection (git commit)
        let expectation = XCTestExpectation(description: "Branch ref change detected")

        let mainRef = gitDir.appendingPathComponent("refs/heads/main")
        let fileDesc = open(mainRef.path, O_EVTONLY)
        XCTAssertGreaterThanOrEqual(fileDesc, 0, "Failed to open branch ref file")

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDesc,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )

        source.setEventHandler {
            expectation.fulfill()
        }

        source.setCancelHandler {
            close(fileDesc)
        }

        source.resume()

        // Simulate commit by updating the branch ref
        try "def789ghi012\n".write(to: mainRef, atomically: true, encoding: .utf8)

        await fulfillment(of: [expectation], timeout: 2.0)
        source.cancel()
    }

    func testParseHEADForBranchRef() throws {
        // Tests parsing HEAD to find the current branch ref
        let headFile = gitDir.appendingPathComponent("HEAD")
        let headContent = try String(contentsOf: headFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertTrue(headContent.hasPrefix("ref: "), "HEAD should start with 'ref: '")

        let refPath = String(headContent.dropFirst(5))
        XCTAssertEqual(refPath, "refs/heads/main", "Should extract branch ref path")

        // Verify the ref file exists
        let branchRefURL = gitDir.appendingPathComponent(refPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: branchRefURL.path))
    }

    func testDetachedHEADHasNoRefPrefix() throws {
        // Tests handling of detached HEAD (direct commit hash)
        let headFile = gitDir.appendingPathComponent("HEAD")

        // Simulate detached HEAD (direct commit hash, no ref:)
        try "abc123def456789\n".write(to: headFile, atomically: true, encoding: .utf8)

        let headContent = try String(contentsOf: headFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertFalse(headContent.hasPrefix("ref: "), "Detached HEAD should not have ref: prefix")
    }

    func testWatcherDetectsIndexChange() async throws {
        // Tests staging/unstaging detection (git add/reset)
        let expectation = XCTestExpectation(description: "Index change detected")

        // Create a fake index file
        let indexFile = gitDir.appendingPathComponent("index")
        try Data([0x44, 0x49, 0x52, 0x43]).write(to: indexFile) // DIRC header

        let fileDesc = open(indexFile.path, O_EVTONLY)
        XCTAssertGreaterThanOrEqual(fileDesc, 0, "Failed to open index file")

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDesc,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )

        source.setEventHandler {
            expectation.fulfill()
        }

        source.setCancelHandler {
            close(fileDesc)
        }

        source.resume()

        // Simulate staging by modifying the index
        try Data([0x44, 0x49, 0x52, 0x43, 0x00]).write(to: indexFile)

        await fulfillment(of: [expectation], timeout: 2.0)
        source.cancel()
    }
}

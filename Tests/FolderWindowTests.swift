import XCTest
@testable import Redmargin

final class FolderWindowTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderWindowTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    @MainActor
    func testOpenFolderCreatesWindow() throws {
        let appDelegate = AppDelegate()

        appDelegate.openFolder(tempDir)

        let standardized = tempDir.standardizedFileURL
        let window = appDelegate.folderWindows[standardized]
        XCTAssertNotNil(window, "openFolder should create a window tracked in folderWindows")

        window?.close()
    }

    @MainActor
    func testOpenFolderDeduplication() throws {
        let appDelegate = AppDelegate()

        appDelegate.openFolder(tempDir)
        let standardized = tempDir.standardizedFileURL
        let firstWindow = appDelegate.folderWindows[standardized]
        XCTAssertNotNil(firstWindow)

        appDelegate.openFolder(tempDir)
        let secondWindow = appDelegate.folderWindows[standardized]

        XCTAssertTrue(firstWindow === secondWindow, "Opening the same folder twice should reuse the existing window")
        XCTAssertEqual(appDelegate.folderWindows.count, 1, "Should only have one folder window")

        firstWindow?.close()
    }

    @MainActor
    func testFolderDetectionInOpenURLs() throws {
        let appDelegate = AppDelegate()

        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: tempDir.path, isDirectory: &isDir)
        XCTAssertTrue(exists)
        XCTAssertTrue(isDir.boolValue, "tempDir should be detected as a directory")

        appDelegate.openFolder(tempDir)

        let standardized = tempDir.standardizedFileURL
        XCTAssertNotNil(
            appDelegate.folderWindows[standardized],
            "Directory URL should be routed to openFolder"
        )
        XCTAssertTrue(
            appDelegate.remoteDocumentWindows.isEmpty,
            "Directory should not create a document window"
        )

        appDelegate.folderWindows[standardized]?.close()
    }
}

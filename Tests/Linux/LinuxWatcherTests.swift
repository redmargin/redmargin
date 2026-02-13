#if os(Linux)
import XCTest
import Foundation
@testable import redmargin_server

final class LinuxWatcherTests: XCTestCase {

    var tempDir: URL!
    var testFile: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LinuxWatcherTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        testFile = tempDir.appendingPathComponent("test.md")
        try "initial content".write(to: testFile, atomically: true, encoding: .utf8)
    }

    override func tearDown() async throws {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    /// Atomic save (write temp file + rename over original) should trigger onChange
    /// and the watcher should keep working for subsequent changes.
    func testWatcherSurvivesAtomicSave() async throws {
        let firstChange = XCTestExpectation(description: "First atomic save detected")
        let secondChange = XCTestExpectation(description: "Second atomic save detected")
        var changeCount = 0

        guard let watcher = LinuxWatcher(path: testFile.path, onChange: {
            changeCount += 1
            if changeCount == 1 { firstChange.fulfill() }
            if changeCount >= 2 { secondChange.fulfill() }
        }) else {
            XCTFail("Failed to create LinuxWatcher")
            return
        }

        // Give watcher time to set up
        try await Task.sleep(nanoseconds: 100_000_000)

        // First atomic save (simulates editor save: write temp + rename)
        try "first edit".write(to: testFile, atomically: true, encoding: .utf8)
        await fulfillment(of: [firstChange], timeout: 5.0)

        // Wait for watcher restart (retry delay is 0.1s minimum)
        try await Task.sleep(nanoseconds: 500_000_000)

        // Second atomic save — watcher should still be alive
        try "second edit".write(to: testFile, atomically: true, encoding: .utf8)
        await fulfillment(of: [secondChange], timeout: 5.0)

        XCTAssertGreaterThanOrEqual(changeCount, 2, "Watcher should detect both atomic saves")
        watcher.stop()
    }

    /// File deletion triggers retry logic and watcher recovers when file reappears.
    func testWatcherRetriesOnDeleteSelf() async throws {
        let deletionDetected = XCTestExpectation(description: "Deletion/recovery detected")
        var changeCount = 0

        guard let watcher = LinuxWatcher(path: testFile.path, onChange: {
            changeCount += 1
            deletionDetected.fulfill()
        }) else {
            XCTFail("Failed to create LinuxWatcher")
            return
        }

        // Give watcher time to set up
        try await Task.sleep(nanoseconds: 100_000_000)

        // Delete the file
        try FileManager.default.removeItem(at: testFile)

        // Recreate it after a short delay (watcher should retry and pick it up)
        try await Task.sleep(nanoseconds: 200_000_000)
        try "recreated content".write(to: testFile, atomically: true, encoding: .utf8)

        await fulfillment(of: [deletionDetected], timeout: 5.0)
        XCTAssertGreaterThanOrEqual(changeCount, 1, "Watcher should detect recovery after delete")

        watcher.stop()
    }
}
#endif

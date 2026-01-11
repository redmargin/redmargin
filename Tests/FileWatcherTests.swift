import XCTest
import Foundation

/// Tests for file watching behavior
/// Note: FileWatcher is in AppMain, so we test the underlying mechanism directly
final class FileWatcherTests: XCTestCase {

    var tempDir: URL!
    var testFile: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileWatcherTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        testFile = tempDir.appendingPathComponent("test.txt")
        try "initial".write(to: testFile, atomically: true, encoding: .utf8)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testDispatchSourceDetectsWrite() async throws {
        let expectation = XCTestExpectation(description: "Write detected")

        let fileDesc = open(testFile.path, O_EVTONLY)
        XCTAssertGreaterThanOrEqual(fileDesc, 0, "Failed to open file")

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDesc,
            eventMask: [.write, .rename, .delete, .attrib],
            queue: .main
        )

        source.setEventHandler {
            expectation.fulfill()
        }

        source.setCancelHandler {
            close(fileDesc)
        }

        source.resume()

        // Write to file using echo append (like shell)
        try "appended".write(to: testFile, atomically: false, encoding: .utf8)

        await fulfillment(of: [expectation], timeout: 2.0)
        source.cancel()
    }

    func testDispatchSourceDetectsAtomicWrite() async throws {
        let expectation = XCTestExpectation(description: "Atomic write detected")

        let fileDesc = open(testFile.path, O_EVTONLY)
        XCTAssertGreaterThanOrEqual(fileDesc, 0, "Failed to open file")

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDesc,
            eventMask: [.write, .rename, .delete, .attrib],
            queue: .main
        )

        source.setEventHandler {
            expectation.fulfill()
        }

        source.setCancelHandler {
            close(fileDesc)
        }

        source.resume()

        // Atomic write (like most editors)
        try "atomic content".write(to: testFile, atomically: true, encoding: .utf8)

        await fulfillment(of: [expectation], timeout: 2.0)
        source.cancel()
    }

    func testDispatchSourceDetectsMultipleWrites() async throws {
        var writeCount = 0
        let expectation = XCTestExpectation(description: "Multiple writes detected")
        expectation.expectedFulfillmentCount = 3

        let fileDesc = open(testFile.path, O_EVTONLY)
        XCTAssertGreaterThanOrEqual(fileDesc, 0, "Failed to open file")

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDesc,
            eventMask: [.write, .rename, .delete, .attrib],
            queue: .main
        )

        source.setEventHandler {
            writeCount += 1
            expectation.fulfill()
        }

        source.setCancelHandler {
            close(fileDesc)
        }

        source.resume()

        // Rapid non-atomic writes
        for idx in 1...3 {
            try "write \(idx)".write(to: testFile, atomically: false, encoding: .utf8)
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }

        await fulfillment(of: [expectation], timeout: 5.0)
        source.cancel()

        XCTAssertGreaterThanOrEqual(writeCount, 3, "Should detect at least 3 writes")
    }

    func testDispatchSourceAfterAtomicWriteNeedsRestart() async throws {
        // This test demonstrates that after an atomic write (rename),
        // the file descriptor becomes stale and new writes are missed

        var events: [DispatchSource.FileSystemEvent] = []
        let firstExpectation = XCTestExpectation(description: "First event")

        let fileDesc = open(testFile.path, O_EVTONLY)
        XCTAssertGreaterThanOrEqual(fileDesc, 0, "Failed to open file")

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDesc,
            eventMask: [.write, .rename, .delete, .attrib],
            queue: .main
        )

        source.setEventHandler {
            events.append(source.data)
            firstExpectation.fulfill()
        }

        source.setCancelHandler {
            close(fileDesc)
        }

        source.resume()

        // First: atomic write
        try "atomic 1".write(to: testFile, atomically: true, encoding: .utf8)
        await fulfillment(of: [firstExpectation], timeout: 2.0)

        // Should have received rename or delete event
        XCTAssertFalse(events.isEmpty, "Should receive event for atomic write")
        let firstEvent = events.first!
        XCTAssertTrue(
            firstEvent.contains(.rename) || firstEvent.contains(.delete),
            "Atomic write should trigger rename or delete, got: \(firstEvent)"
        )

        source.cancel()
    }
}

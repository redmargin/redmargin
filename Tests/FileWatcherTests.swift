import XCTest
import Foundation
import AppKit
@testable import RedmarginLib
@testable import RedmarginCore

/// Tests for file watching behavior
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

    // MARK: - writeOnly (attribute) Regression

    /// Regression for the macOS remote-helper file-descriptor exhaustion: the git
    /// metadata / single-file watchers must be writeOnly so an access-time or
    /// permission (`.attrib`) change does NOT fire onChange. Reading a watched file
    /// (e.g. a watch-driven `git status` reading `.git/index`) bumps its access time;
    /// if that re-fired the watcher it formed a runaway watch->read->watch loop that
    /// spawned git until the helper daemon ran out of file descriptors.
    func testWriteOnlyWatcherIgnoresAttributeOnlyChange() async throws {
        let fired = XCTestExpectation(description: "writeOnly watcher must not fire on attrib-only change")
        fired.isInverted = true

        let watcher = FileWatcher(url: testFile, writeOnly: true, onChange: {
            fired.fulfill()
        })
        XCTAssertNotNil(watcher)

        // chmod is an attribute-only change (no content write).
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: testFile.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: testFile.path)

        await fulfillment(of: [fired], timeout: 1.5)
        _ = watcher
    }

    /// The writeOnly watcher must still detect real content writes.
    func testWriteOnlyWatcherStillDetectsWrites() async throws {
        let fired = XCTestExpectation(description: "writeOnly watcher fires on write")

        let watcher = FileWatcher(url: testFile, writeOnly: true, onChange: {
            fired.fulfill()
        })
        XCTAssertNotNil(watcher)

        try "new content".write(to: testFile, atomically: false, encoding: .utf8)

        await fulfillment(of: [fired], timeout: 3.0)
        _ = watcher
    }

    // MARK: - Idle Recovery Tests

    func testWatcherCallsOnDiedAfterRetryExhaustion() async throws {
        // Create a watcher on a file, then delete it so retries exhaust
        let diedExpectation = XCTestExpectation(description: "onWatcherDied fires")

        let watcher = FileWatcher(url: testFile, onChange: {})
        XCTAssertNotNil(watcher)

        watcher!.onWatcherDied = {
            diedExpectation.fulfill()
        }

        // Delete the file so the watcher can't restart
        try FileManager.default.removeItem(at: testFile)

        // Force a restart by simulating an atomic write scenario —
        // the file is already gone, so trigger restartWatching via a rename event.
        // We can do this by writing to the parent dir's temp file and renaming,
        // but since the file is deleted, the watcher's dispatch source should fire
        // a delete event which triggers restartWatching internally.
        // The watcher's dispatch source detects the delete and calls restartWatching,
        // which retries 5 times with exponential backoff (0.1, 0.2, 0.5, 1.0, 2.0 = ~3.8s total)

        await fulfillment(of: [diedExpectation], timeout: 10.0)
    }

    func testWatcherRecreatesAfterSimulatedWake() async throws {
        let changeExpectation = XCTestExpectation(description: "File change detected after wake")

        var changeCount = 0
        let watcher = FileWatcher(url: testFile, onChange: {
            changeCount += 1
            if changeCount >= 2 {
                // First change is from the wake recreation itself (fire onChange)
                // Second change would be from the actual file write
                changeExpectation.fulfill()
            }
        })
        XCTAssertNotNil(watcher)

        // Post didWakeNotification to simulate system wake
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        // Give the wake handler a moment to recreate
        try await Task.sleep(nanoseconds: 200_000_000)

        // Write to the file — watcher should still detect it after recreation
        try "post-wake content".write(to: testFile, atomically: true, encoding: .utf8)

        await fulfillment(of: [changeExpectation], timeout: 5.0)
    }

    func testGitRepoWatcherRecreatesAfterSimulatedWake() async throws {
        // Create a temp git repo
        let repoDir = tempDir.appendingPathComponent("git-repo")
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)

        let gitDir = repoDir.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)

        let refsDir = gitDir.appendingPathComponent("refs/heads")
        try FileManager.default.createDirectory(at: refsDir, withIntermediateDirectories: true)

        // Create HEAD pointing to main
        let headURL = gitDir.appendingPathComponent("HEAD")
        try "ref: refs/heads/main\n".write(to: headURL, atomically: true, encoding: .utf8)

        // Create index file
        let indexURL = gitDir.appendingPathComponent("index")
        try "fake-index".write(to: indexURL, atomically: true, encoding: .utf8)

        // Create the branch ref
        let refURL = refsDir.appendingPathComponent("main")
        try "abc123\n".write(to: refURL, atomically: true, encoding: .utf8)

        let changeExpectation = XCTestExpectation(description: "Git change detected after wake")

        var changeDetected = false
        let watcher = GitRepoWatcher(repoRoot: repoDir.path) {
            if !changeDetected {
                changeDetected = true
                changeExpectation.fulfill()
            }
        }
        _ = watcher  // Keep alive

        // Post wake notification
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        // Give wake handlers a moment to recreate, then modify index
        try await Task.sleep(nanoseconds: 300_000_000)
        try "modified-index".write(to: indexURL, atomically: true, encoding: .utf8)

        await fulfillment(of: [changeExpectation], timeout: 5.0)
    }
}

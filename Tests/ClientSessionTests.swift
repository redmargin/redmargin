import XCTest
@testable import redmargin_server

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A `ClientSession` must not touch its descriptor once `close()` has returned.
/// The daemon closes the descriptor there and `accept()` immediately reuses that
/// number for the next client, so a late response would otherwise land in a
/// stranger's stream.
final class ClientSessionTests: XCTestCase {

    /// Returns a connected pair: `.server` is handed to the session, `.client`
    /// stands in for the peer that reads what the session writes.
    private func makeSocketPair() throws -> (server: Int32, client: Int32) {
        var fds: [Int32] = [0, 0]
        let result = socketpair(AF_UNIX, sockStreamType, 0, &fds)
        try XCTSkipIf(result != 0, "socketpair() unavailable: errno \(errno)")
        return (fds[0], fds[1])
    }

    private var sockStreamType: Int32 {
        #if os(Linux)
        return Int32(SOCK_STREAM.rawValue)
        #else
        return SOCK_STREAM
        #endif
    }

    /// True when the descriptor has bytes (or an EOF) ready within `timeout`.
    /// Every read below goes through this so a socket whose peer is still open
    /// cannot block the suite.
    private func isReadable(_ fileDesc: Int32, timeout: TimeInterval) -> Bool {
        var descriptor = pollfd(fd: fileDesc, events: Int16(POLLIN), revents: 0)
        return poll(&descriptor, 1, Int32(timeout * 1000)) > 0
    }

    /// Reads whatever arrives within `timeout`, returning nil on EOF or silence.
    private func readAvailable(_ fileDesc: Int32, timeout: TimeInterval = 0.5, max: Int = 256) -> Data? {
        guard isReadable(fileDesc, timeout: timeout) else { return nil }
        var buffer = [UInt8](repeating: 0, count: max)
        let count = read(fileDesc, &buffer, max)
        if count <= 0 { return nil }
        return Data(buffer[0..<count])
    }

    /// Waits for the session's write queue to drain the expected frame.
    private func waitForBytes(on fileDesc: Int32, expected: Data) -> Data? {
        var received = Data()
        let deadline = Date().addingTimeInterval(2)
        while received.count < expected.count && Date() < deadline {
            guard let chunk = readAvailable(fileDesc, timeout: 0.25) else { break }
            received.append(chunk)
        }
        return received.isEmpty ? nil : received
    }

    func testSendBeforeCloseReachesThePeer() throws {
        let pair = try makeSocketPair()
        defer { close(pair.client) }

        let session = ClientSession(clientFD: pair.server)
        let frame = Data("hello".utf8)
        session.send(frame)

        XCTAssertEqual(waitForBytes(on: pair.client, expected: frame), frame)
        session.close()
    }

    /// The regression, reproduced exactly as the daemon hits it: the session's
    /// descriptor is closed, `accept()` (here, `socketpair()`) hands the same
    /// descriptor number to the next client, and a response from the *previous*
    /// connection resolves late. The late frame must not reach the new client.
    func testLateSendDoesNotWriteIntoRecycledDescriptor() throws {
        let first = try makeSocketPair()
        close(first.client)

        let session = ClientSession(clientFD: first.server)
        let retiredFD = session.fileDescriptor
        session.close()

        // The kernel hands out the lowest free descriptor, so the next socket
        // reclaims the number the session just released.
        let second = try makeSocketPair()
        defer { close(second.server); close(second.client) }
        try XCTSkipIf(
            second.server != retiredFD,
            "Descriptor \(retiredFD) was not recycled (got \(second.server)); cannot exercise the race"
        )

        session.send(Data("late response from the previous connection".utf8))

        // Give the write queue a chance to run the dropped block.
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertNil(
            readAvailable(second.client),
            "A late frame from a closed session was written into the next client's connection"
        )
    }

    /// A frame sent after close never reaches the original peer either; it sees
    /// only the EOF that close produced.
    func testSendAfterCloseIsDropped() throws {
        let pair = try makeSocketPair()
        defer { close(pair.client) }

        let session = ClientSession(clientFD: pair.server)
        let firstFrame = Data("first".utf8)
        session.send(firstFrame)
        XCTAssertEqual(waitForBytes(on: pair.client, expected: firstFrame), firstFrame)

        session.close()
        session.send(Data("late response".utf8))

        // The peer sees EOF from the close, and never the late frame.
        XCTAssertNil(readAvailable(pair.client), "A frame sent after close() reached the peer")
    }

    /// `close()` must release the descriptor itself; the daemon relies on that to
    /// hand the number back to `accept()`.
    func testCloseReleasesTheDescriptor() throws {
        let pair = try makeSocketPair()
        defer { close(pair.client) }

        let session = ClientSession(clientFD: pair.server)
        session.close()

        var byte: UInt8 = 0
        let result = write(pair.server, &byte, 1)
        XCTAssertEqual(result, -1, "Descriptor was still open after close()")
        XCTAssertEqual(errno, EBADF)
    }

    /// A request still awaiting its handler when the client disconnects must be
    /// cancelled rather than left to complete and write.
    func testCloseCancelsInFlightRequests() throws {
        let pair = try makeSocketPair()
        defer { close(pair.client) }

        let session = ClientSession(clientFD: pair.server)
        let started = XCTestExpectation(description: "request started")
        let observedCancellation = XCTestExpectation(description: "request observed cancellation")

        session.spawnRequest {
            started.fulfill()
            // Outlive the read loop the way a slow RPC handler would.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
            observedCancellation.fulfill()
        }

        wait(for: [started], timeout: 2)
        session.close()
        wait(for: [observedCancellation], timeout: 2)
    }

    /// After teardown the session refuses to adopt new work, so a message parsed
    /// from the tail of a closing connection cannot resurrect it.
    func testSpawnRequestAfterCloseDoesNotRun() throws {
        let pair = try makeSocketPair()
        defer { close(pair.client) }

        let session = ClientSession(clientFD: pair.server)
        session.close()

        let didRun = XCTestExpectation(description: "request ran")
        didRun.isInverted = true
        session.spawnRequest { didRun.fulfill() }

        wait(for: [didRun], timeout: 0.5)
    }
}

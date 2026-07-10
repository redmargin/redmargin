import XCTest
@testable import RedmarginCore

/// Test-only access to the transport internals. Kept out of the production actor
/// so no shipping code carries a seam that only tests need.
extension SSHConnection {
    /// Puts the connection into the state `send()` requires, writing to `stdin`
    /// instead of a real SSH process.
    func configureForTesting(stdin: Pipe) {
        self.stdinPipe = stdin
        self.state = .connected
    }

    func pendingRequestCount() -> Int { pendingRequestIds.count }
    func completedResponseCount() -> Int { completedResponses.count }
}

/// Covers how a shared per-host connection routes what comes back from the
/// helper: responses to the request that is waiting for them, and push events to
/// every window rather than an arbitrary one.
final class SSHConnectionRoutingTests: XCTestCase {

    private func pushEventFrame(path: String) throws -> Data {
        try RPCStreamHandler.encode(
            id: nil,
            type: RPCMessageType.fileChanged.rawValue,
            payload: FileChangedPayload(path: path, changeType: "modified")
        )
    }

    private func responseFrame(id: Int, content: String) throws -> Data {
        try RPCStreamHandler.encode(
            id: id,
            type: RPCMessageType.readFile.rawValue,
            payload: ReadFileResponsePayload(content: content, error: nil)
        )
    }

    /// Collects the first event from a subscriber, or nil if none arrives in time.
    private func firstEvent(from stream: AsyncStream<Data>, timeout: TimeInterval = 2) async -> Data? {
        await withTaskGroup(of: Data?.self) { group in
            group.addTask {
                for await event in stream { return event }
                return nil
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    // MARK: - Push event fan-out

    /// The regression: windows on one host share a connection. A single-consumer
    /// stream hands each event to whichever iterator happens to be waiting, so the
    /// window that asked for the watch can miss its own file's change.
    func testPushEventReachesEverySubscriber() async throws {
        let connection = SSHConnection(host: "fanout-test")
        let first = await connection.addEventSubscriber()
        let second = await connection.addEventSubscriber()
        let third = await connection.addEventSubscriber()

        let frame = try pushEventFrame(path: "/tmp/watched.md")
        await connection.processIncomingData(frame)

        async let firstEventData = firstEvent(from: first.stream)
        async let secondEventData = firstEvent(from: second.stream)
        async let thirdEventData = firstEvent(from: third.stream)

        let received = await [firstEventData, secondEventData, thirdEventData]
        XCTAssertEqual(received.compactMap { $0 }.count, 3, "A push event was delivered to only some windows")
    }

    func testRemovedSubscriberStopsReceivingEvents() async throws {
        let connection = SSHConnection(host: "fanout-test")
        let retained = await connection.addEventSubscriber()
        let released = await connection.addEventSubscriber()

        await connection.removeEventSubscriber(released.id)
        await connection.processIncomingData(try pushEventFrame(path: "/tmp/watched.md"))

        let retainedEvent = await firstEvent(from: retained.stream)
        XCTAssertNotNil(retainedEvent, "The remaining window stopped receiving events")

        // The released subscriber's stream is finished, so it yields nothing.
        let releasedEvent = await firstEvent(from: released.stream, timeout: 0.3)
        XCTAssertNil(releasedEvent)

        let count = await connection.eventSubscriberCount()
        XCTAssertEqual(count, 1)
    }

    /// A provider must release its subscription when it goes away, or the
    /// connection accumulates one continuation per document ever opened.
    func testProviderReleasesItsSubscriptionOnTeardown() async throws {
        let connection = SSHConnection(host: "fanout-test")

        var provider: RemoteFileProvider? = RemoteFileProvider(connection: connection)
        XCTAssertNotNil(provider)
        try await waitForSubscriberCount(1, on: connection)

        provider = nil
        try await waitForSubscriberCount(0, on: connection)
    }

    func testEachProviderGetsItsOwnSubscription() async throws {
        let connection = SSHConnection(host: "fanout-test")
        let providers = [
            RemoteFileProvider(connection: connection),
            RemoteFileProvider(connection: connection)
        ]

        try await waitForSubscriberCount(2, on: connection)
        withExtendedLifetime(providers) {}
    }

    private func waitForSubscriberCount(
        _ expected: Int,
        on connection: SSHConnection,
        timeout: TimeInterval = 2
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await connection.eventSubscriberCount() == expected { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let actual = await connection.eventSubscriberCount()
        XCTFail("Expected \(expected) event subscribers, found \(actual)")
    }

    // MARK: - Request registration

    /// The regression: `send()` suspends to write on a serial queue, and the actor
    /// can be re-entered during that suspension. A response that arrives while the
    /// write is still in flight must be matched to its request, not discarded as
    /// unsolicited, which would strand the caller until its timeout tore down a
    /// healthy connection.
    ///
    /// The write is made to block by filling the pipe buffer, so the response is
    /// delivered at a point the write provably has not completed.
    func testResponseArrivingDuringWriteIsMatchedToItsRequest() async throws {
        let connection = SSHConnection(host: "registration-test")
        let pipe = Pipe()
        await connection.configureForTesting(stdin: pipe)

        // Larger than the pipe buffer, so the write blocks until it is drained.
        let oversizedPath = String(repeating: "p", count: 512 * 1024)

        let sendTask = Task {
            try await connection.send(
                type: RPCMessageType.readFile.rawValue,
                payload: ReadFilePayload(path: oversizedPath),
                timeout: 10,
                disconnectOnTimeout: false
            )
        }

        // Let send() reach its blocked write, then confirm it really is stuck there.
        try await Task.sleep(nanoseconds: 300_000_000)
        let pending = await connection.pendingRequestCount()
        XCTAssertEqual(pending, 1, "send() reached its write without registering the request first")

        // Deliver the response while the write is still blocked.
        await connection.processIncomingData(try responseFrame(id: 1, content: "hello"))

        // Now drain the pipe so the write can finish and send() can resume.
        let drain = Task.detached {
            let handle = pipe.fileHandleForReading
            var drained = 0
            while drained < oversizedPath.utf8.count {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                drained += chunk.count
            }
        }

        let data = try await sendTask.value
        _ = await drain.result

        let response = try JSONDecoder().decode(RPCMessage<ReadFileResponsePayload>.self, from: data)
        XCTAssertEqual(response.payload.content, "hello")

        let leftoverPending = await connection.pendingRequestCount()
        let leftoverResponses = await connection.completedResponseCount()
        XCTAssertEqual(leftoverPending, 0, "A completed request stayed pending")
        XCTAssertEqual(leftoverResponses, 0, "A claimed response stayed buffered")
    }

    /// A request that times out must leave nothing behind, or `completedResponses`
    /// grows for the life of the connection.
    func testTimedOutRequestLeavesNoPendingState() async throws {
        let connection = SSHConnection(host: "registration-test")
        await connection.configureForTesting(stdin: Pipe())

        do {
            _ = try await connection.send(
                type: RPCMessageType.readFile.rawValue,
                payload: ReadFilePayload(path: "/tmp/never-answered.md"),
                timeout: 0.3,
                disconnectOnTimeout: false
            )
            XCTFail("Expected the request to time out")
        } catch {
            // Expected.
        }

        let pending = await connection.pendingRequestCount()
        let responses = await connection.completedResponseCount()
        XCTAssertEqual(pending, 0)
        XCTAssertEqual(responses, 0)
    }

    /// A cancelled request must clean up the same way a timed-out one does.
    func testCancelledRequestLeavesNoPendingState() async throws {
        let connection = SSHConnection(host: "registration-test")
        await connection.configureForTesting(stdin: Pipe())

        let sendTask = Task {
            try await connection.send(
                type: RPCMessageType.readFile.rawValue,
                payload: ReadFilePayload(path: "/tmp/cancelled.md"),
                timeout: 10,
                disconnectOnTimeout: false
            )
        }

        try await Task.sleep(nanoseconds: 200_000_000)
        sendTask.cancel()
        _ = await sendTask.result

        let pending = await connection.pendingRequestCount()
        let responses = await connection.completedResponseCount()
        XCTAssertEqual(pending, 0, "A cancelled request stayed pending")
        XCTAssertEqual(responses, 0)
    }
}

import Foundation
import RedmarginCore

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Owns one accepted client connection: its descriptor, the serial queue that
/// writes to it, and the request tasks it spawned.
///
/// Everything that can outlive the read loop (queued writes, in-flight request
/// tasks, watcher events) is routed through here, so it can all be shut off
/// *before* the descriptor is closed. Without that gate a late response writes
/// through a descriptor number that `accept()` has already handed to the next
/// client, corrupting its framing and leaking the previous response to it.
final class ClientSession {
    private let clientFD: Int32
    private let writeQueue: DispatchQueue

    /// Touched only on `writeQueue`, which serializes it against every write.
    private var isClosed = false

    private let taskLock = NSLock()
    private var requestTasks: [UUID: Task<Void, Never>] = [:]
    private var acceptsNewTasks = true

    /// The descriptor to read from. Valid only until `close()` returns.
    var fileDescriptor: Int32 { clientFD }

    init(clientFD: Int32) {
        self.clientFD = clientFD
        self.writeQueue = DispatchQueue(label: "com.redmargin.server.write.\(clientFD)")
    }

    /// Queues a frame for this connection. Frames submitted after `close()` are
    /// dropped: the descriptor may already belong to another client.
    func send(_ data: Data) {
        writeQueue.async { [self] in
            guard !isClosed else { return }
            let delivered = data.withUnsafeBytes { raw -> Bool in
                guard let base = raw.baseAddress else { return true }
                return socketWriteAll(fileDesc: clientFD, buffer: base, count: data.count)
            }
            if !delivered {
                // Peer hung up (EPIPE/ECONNRESET). Stop writing to this client.
                isClosed = true
            }
        }
    }

    /// Runs a request handler as a tracked task so teardown can cancel it.
    /// The registry is mutated under `taskLock`, which the task's own
    /// completion path also takes, so a handler that finishes immediately
    /// cannot remove its entry before it is inserted.
    func spawnRequest(_ body: @escaping @Sendable () async -> Void) {
        let id = UUID()
        taskLock.lock()
        defer { taskLock.unlock() }
        guard acceptsNewTasks else { return }
        requestTasks[id] = Task { [self] in
            await body()
            finishRequest(id)
        }
    }

    private func finishRequest(_ id: UUID) {
        taskLock.lock()
        requestTasks.removeValue(forKey: id)
        taskLock.unlock()
    }

    /// Stops new work, cancels what is still running, drains queued writes, and
    /// only then closes the descriptor.
    func close() {
        taskLock.lock()
        acceptsNewTasks = false
        let inFlight = Array(requestTasks.values)
        requestTasks.removeAll()
        taskLock.unlock()
        for task in inFlight { task.cancel() }

        // Barrier. This block runs after every write already queued, so nothing
        // is mid-write when it returns; every write queued after it observes
        // `isClosed` and drops. Only now is the descriptor safe to release.
        writeQueue.sync { isClosed = true }
        _ = systemClose(clientFD)
    }
}

enum Daemon {
    @_silgen_name("fork")
    static func c_fork() -> Int32

    static func start(pidFile: String, stdinSocket: String, stdoutSocket: String, stderrSocket: String) {
        fputs("Starting daemon...\n", stderr)

        // NOTE: We intentionally do NOT fork here.
        // fork() breaks GCD/dispatch queues and Swift async/await because threads
        // are not duplicated. The daemon uses both for connection handling.
        // Instead, the proxy spawns us and we run in foreground.
        // The proxy's Process.waitUntilExit() will return when we exit.

        // 1. Write PID file
        do {
            let currentPid = String(ProcessInfo.processInfo.processIdentifier)
            try currentPid.write(toFile: pidFile, atomically: true, encoding: .utf8)
        } catch {
            fputs("Failed to write PID file: \(error)\n", stderr)
            exit(1)
        }

        // 4. Listen on RPC socket
        // We use stdinSocket path as the main RPC channel
        let listener = UnixSocketListener(path: stdinSocket)
        do {
            try listener.start()
        } catch {
            fputs("Failed to start listener: \(error)\n", stderr)
            exit(1)
        }

        fputs("Daemon listening on \(stdinSocket)\n", stderr)

        // 4. Accept Loop
        while true {
            let clientFD = listener.acceptConnection()
            if clientFD < 0 {
                // Classify the accept() failure instead of spinning. A bare
                // `continue` pegs a CPU core forever when the error is
                // persistent (descriptor exhaustion, or a dead listener FD).
                let err = errno
                if err == EBADF || err == EINVAL || err == ENOTSOCK {
                    fputs("accept() fatal (errno \(err)); exiting accept loop\n", stderr)
                    break
                }
                if err == EMFILE || err == ENFILE {
                    // Out of descriptors: back off so we do not busy-spin while
                    // whatever leaked them is (hopefully) released.
                    fputs("accept() out of descriptors (errno \(err)); backing off\n", stderr)
                    usleep(100_000) // 100ms
                }
                // EINTR / ECONNABORTED / EAGAIN: transient, retry immediately.
                continue
            }

            // Socket and directory modes should already keep other users out. This
            // is the backstop: the RPC channel is unauthenticated, so a peer that is
            // not this account never gets to issue file operations through it.
            if let peerUID = socketPeerUID(fileDesc: clientFD), peerUID != getuid() {
                fputs("Rejecting connection from uid \(peerUID)\n", stderr)
                _ = systemClose(clientFD)
                continue
            }

            fputs("Accepted connection\n", stderr)

            // Handle each connection concurrently with its OWN RPC handler and
            // stream handler. A shared handler let a second connection overwrite
            // the first's event routing and let either disconnect tear down every
            // client's watchers; a per-connection handler isolates event routing
            // and scopes watcher teardown to the connection that is closing.
            DispatchQueue.global().async {
                let rpcHandler = RPCHandler()
                let streamHandler = RPCStreamHandler()
                let session = ClientSession(clientFD: clientFD)
                handleClient(session: session, rpcHandler: rpcHandler, streamHandler: streamHandler)
                // Cancel this connection's request tasks and drain its queued
                // writes before the descriptor is released back to accept().
                session.close()
                // Release only this connection's watchers so their inotify FDs do
                // not accumulate; other live connections keep theirs.
                let teardown = DispatchSemaphore(value: 0)
                Task {
                    await rpcHandler.stopAllWatchers()
                    teardown.signal()
                }
                teardown.wait()
                fputs("Connection closed, watchers released\n", stderr)
            }
        }
    }

    static func handleClient(
        session: ClientSession,
        rpcHandler: RPCHandler,
        streamHandler: RPCStreamHandler
    ) {
        let sendData: (Data) -> Void = { data in session.send(data) }

        // Setup event handlers SYNCHRONOUSLY before processing any requests
        // This prevents race condition where watchFile request is processed before handlers are set
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await rpcHandler.fileOperations.setEventHandler(sendData)
            await rpcHandler.gitOperations.setEventHandler(sendData)
            semaphore.signal()
        }
        semaphore.wait()

        let bufferSize = 4096
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 1)
        defer { buffer.deallocate() }

        while true {
            let readCount = socketRead(fileDesc: session.fileDescriptor, buffer: buffer, count: bufferSize)
            if readCount <= 0 { break }

            let data = Data(bytes: buffer, count: readCount)
            let messages = streamHandler.receive(data: data)

            for msgData in messages {
                session.spawnRequest {
                    if let response = await rpcHandler.handle(msgData) {
                        session.send(response)
                    }
                }
            }
        }
    }
}

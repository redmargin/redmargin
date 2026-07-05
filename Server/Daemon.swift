import Foundation
import RedmarginCore

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

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

            fputs("Accepted connection\n", stderr)

            // Handle each connection concurrently with its OWN RPC handler and
            // stream handler. A shared handler let a second connection overwrite
            // the first's event routing and let either disconnect tear down every
            // client's watchers; a per-connection handler isolates event routing
            // and scopes watcher teardown to the connection that is closing.
            DispatchQueue.global().async {
                let rpcHandler = RPCHandler()
                let streamHandler = RPCStreamHandler()
                handleClient(clientFD: clientFD, rpcHandler: rpcHandler, streamHandler: streamHandler)
                _ = systemClose(clientFD)
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
        clientFD: Int32,
        rpcHandler: RPCHandler,
        streamHandler: RPCStreamHandler
    ) {
        let writeQueue = DispatchQueue(label: "com.redmargin.server.write")

        // Helper to write data safely
        let sendData: (Data) -> Void = { data in
            writeQueue.async {
                data.withUnsafeBytes { ptr in
                    if let baseAddress = ptr.baseAddress {
                        _ = socketWriteAll(fileDesc: clientFD, buffer: baseAddress, count: data.count)
                    }
                }
            }
        }

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
            let readCount = socketRead(fileDesc: clientFD, buffer: buffer, count: bufferSize)
            if readCount <= 0 { break }

            let data = Data(bytes: buffer, count: readCount)
            let messages = streamHandler.receive(data: data)

            for msgData in messages {
                Task {
                    if let response = await rpcHandler.handle(msgData) {
                        sendData(response)
                    }
                }
            }
        }
    }
}

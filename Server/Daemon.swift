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
        print("Starting daemon...")

        // 1. Fork to background
        // Note: In a real deployment, we might skip this if managed by systemd,
        // but for SSH spawning we need to detach.
        #if os(Linux)
        let pid = c_fork()
        if pid < 0 {
            fatalError("Failed to fork")
        } else if pid > 0 {
            // Parent exits
            exit(0)
        }
        setsid()
        #endif
        // On macOS for dev/testing, we might not fork to keep it simple or use Process.
        // But let's assume we are running directly for now if not linux, or rely on the caller.

        // 2. Write PID file
        do {
            let currentPid = String(ProcessInfo.processInfo.processIdentifier)
            try currentPid.write(toFile: pidFile, atomically: true, encoding: .utf8)
        } catch {
            print("Failed to write PID file: \(error)")
            exit(1)
        }

        // 3. Listen on RPC socket
        // We use stdinSocket path as the main RPC channel
        let listener = UnixSocketListener(path: stdinSocket)
        do {
            try listener.start()
        } catch {
            print("Failed to start listener: \(error)")
            exit(1)
        }

        print("Daemon listening on \(stdinSocket)")

        let rpcHandler = RPCHandler()

        // 4. Accept Loop
        while true {
            let clientFD = listener.acceptConnection()
            if clientFD < 0 {
                continue
            }

            print("Accepted connection")

            // Handle connection concurrently - each connection gets its own stream handler
            DispatchQueue.global().async {
                let streamHandler = RPCStreamHandler()
                handleClient(fd: clientFD, rpcHandler: rpcHandler, streamHandler: streamHandler)
                _ = system_close(clientFD)
                print("Connection closed")
            }
        }
    }

    static func handleClient(fd: Int32, rpcHandler: RPCHandler, streamHandler: RPCStreamHandler) {
        let writeQueue = DispatchQueue(label: "com.redmargin.server.write")

        // Helper to write data safely
        let sendData: (Data) -> Void = { data in
            writeQueue.async {
                data.withUnsafeBytes { ptr in
                    if let baseAddress = ptr.baseAddress {
                        _ = socket_write(fd: fd, buffer: baseAddress, count: data.count)
                    }
                }
            }
        }

        // Setup event handlers
        Task {
            await rpcHandler.fileOperations.setEventHandler(sendData)
            await rpcHandler.gitOperations.setEventHandler(sendData)
        }

        let bufferSize = 4096
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 1)
        defer { buffer.deallocate() }

        while true {
            let readCount = socket_read(fd: fd, buffer: buffer, count: bufferSize)
            if readCount <= 0 {
                break // EOF or Error
            }

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

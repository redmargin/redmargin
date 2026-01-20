import Foundation

enum Proxy {
    static func start(reconnect: Bool) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let serverDir = "\(home)/.redmargin-server"
        let socketPath = "\(serverDir)/rpc.sock"
        let pidFile = "\(serverDir)/daemon.pid"

        // 1. Ensure directory exists
        try? FileManager.default.createDirectory(atPath: serverDir, withIntermediateDirectories: true)

        // 2. Connect to daemon (starting if needed)
        let socketFD = connectToDaemon(socketPath: socketPath, pidFile: pidFile)

        // 3. Bridge stdin/stdout to socket
        bridgeStdioToSocket(socketFD: socketFD)
    }

    private static func connectToDaemon(socketPath: String, pidFile: String) -> Int32 {
        var socketFD = UnixSocketClient.connect(path: socketPath)

        if socketFD < 0 && !isDaemonRunning(pidFile: pidFile) {
            fputs("Daemon not running, starting...\n", stderr)
            startDaemon(pidFile: pidFile, socketPath: socketPath)

            // Wait for socket to be created (max 2 seconds)
            for _ in 1...20 {
                Thread.sleep(forTimeInterval: 0.1)
                socketFD = UnixSocketClient.connect(path: socketPath)
                if socketFD >= 0 { break }
            }
        }

        if socketFD < 0 {
            fputs("Failed to connect to daemon at \(socketPath)\n", stderr)
            exit(1)
        }

        return socketFD
    }

    private static func bridgeStdioToSocket(socketFD: Int32) {
        let group = DispatchGroup()
        group.enter()
        group.enter()

        // Stdin -> Socket
        DispatchQueue.global().async {
            bridgeFileDescriptors(from: 0, to: socketFD)
            group.leave()
        }

        // Socket -> Stdout
        DispatchQueue.global().async {
            bridgeFileDescriptors(from: socketFD, to: 1)
            group.leave()
        }

        group.wait()
        _ = system_close(socketFD)
    }

    private static func bridgeFileDescriptors(from sourceFD: Int32, to destFD: Int32) {
        let bufferSize = 4096
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 1)
        defer { buffer.deallocate() }

        while true {
            let count = socket_read(fd: sourceFD, buffer: buffer, count: bufferSize)
            if count <= 0 { break }
            let written = socket_write(fd: destFD, buffer: buffer, count: count)
            if written < 0 { break }
        }
    }

    private static func isDaemonRunning(pidFile: String) -> Bool {
        guard let pidStr = try? String(contentsOfFile: pidFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int32(pidStr) else {
            return false
        }

        // kill -0 checks if process exists
        return kill(pid, 0) == 0
    }

    private static func startDaemon(pidFile: String, socketPath: String) {
        let binaryPath = CommandLine.arguments[0]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = [
            "run",
            "--pid-file", pidFile,
            "--stdin-socket", socketPath,
            "--stdout-socket", socketPath, // Bidirectional
            "--stderr-socket", "/dev/null"
        ]

        // Redirect daemon's stdout/stderr to /dev/null to avoid corrupting RPC protocol
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            // Daemon mode forks and parent exits immediately
            process.waitUntilExit()
        } catch {
            fputs("Failed to spawn daemon: \(error)\n", stderr)
        }
    }
}

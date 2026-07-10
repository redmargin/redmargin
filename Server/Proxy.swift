import Foundation

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

enum Proxy {
    // Magic sync marker that client waits for before starting protocol parsing.
    // This allows us to discard any garbage from shell initialization (.bashrc, etc.)
    static let syncMarker = "REDMARGIN_SYNC_7f3d9a\n"

    static func start(reconnect: Bool) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let serverDir = "\(home)/.redmargin-server"
        let socketPath = "\(serverDir)/rpc.sock"
        let pidFile = "\(serverDir)/daemon.pid"

        // 1. Ensure directory exists
        try? FileManager.default.createDirectory(atPath: serverDir, withIntermediateDirectories: true)

        // 2. Connect to daemon (starting if needed)
        let socketFD = connectToDaemon(socketPath: socketPath, pidFile: pidFile)

        // 3. Small delay to let daemon accept the connection
        // This is a workaround for the race between connect() and accept()
        Thread.sleep(forTimeInterval: 0.1)

        // 4. Output sync marker - client waits for this before sending
        print(syncMarker, terminator: "")
        fflush(stdout)

        // 5. Bridge stdin/stdout to socket
        bridgeStdioToSocket(socketFD: socketFD)
    }

    private static func connectToDaemon(socketPath: String, pidFile: String) -> Int32 {
        let lockFile = pidFile + ".lock"

        // Try to connect to existing daemon first
        var socketFD = UnixSocketClient.connect(path: socketPath)
        if socketFD >= 0 {
            return socketFD
        }

        // Need to start daemon - use lock file to prevent races
        let lockFD = acquireLock(lockFile: lockFile)
        defer { releaseLock(fileDesc: lockFD, lockFile: lockFile) }

        // Check again after acquiring lock (another process may have started daemon)
        socketFD = UnixSocketClient.connect(path: socketPath)
        if socketFD >= 0 {
            return socketFD
        }

        // We have the lock and daemon isn't running - start it
        fputs("Daemon not running, starting...\n", stderr)
        startDaemon(pidFile: pidFile, socketPath: socketPath)

        // Wait for socket to be created (max 10 seconds)
        // Use usleep instead of Thread.sleep to avoid GCD/async issues
        for _ in 1...100 {
            usleep(100_000) // 100ms
            socketFD = UnixSocketClient.connect(path: socketPath)
            if socketFD >= 0 { return socketFD }
        }

        fputs("Failed to connect to daemon at \(socketPath)\n", stderr)
        exit(1)
    }

    private static func acquireLock(lockFile: String) -> Int32 {
        #if os(Linux)
        let flags = O_CREAT | O_RDWR
        #else
        let flags = O_CREAT | O_RDWR
        #endif
        let lockFD = open(lockFile, flags, 0o644)
        if lockFD < 0 {
            fputs("Warning: Could not create lock file\n", stderr)
            return -1
        }

        // Try to acquire exclusive lock (blocks if another process has it)
        #if os(Linux)
        var lockInfo = flock()
        lockInfo.l_type = Int16(F_WRLCK)
        lockInfo.l_whence = Int16(SEEK_SET)
        lockInfo.l_start = 0
        lockInfo.l_len = 0
        _ = fcntl(lockFD, F_SETLKW, &lockInfo)
        #else
        _ = flock(lockFD, LOCK_EX)
        #endif

        return lockFD
    }

    private static func releaseLock(fileDesc: Int32, lockFile: String) {
        if fileDesc >= 0 {
            #if os(Linux)
            var lockInfo = flock()
            lockInfo.l_type = Int16(F_UNLCK)
            lockInfo.l_whence = Int16(SEEK_SET)
            lockInfo.l_start = 0
            lockInfo.l_len = 0
            _ = fcntl(fileDesc, F_SETLKW, &lockInfo)
            #else
            _ = flock(fileDesc, LOCK_UN)
            #endif
            close(fileDesc)
        }
    }

    private static func bridgeStdioToSocket(socketFD: Int32) {
        let group = DispatchGroup()
        group.enter()
        group.enter()

        // Stdin -> Socket
        DispatchQueue.global().async {
            bridgeFileDescriptors(from: 0, to: socketFD)
            // Signal EOF to the daemon so its socket->stdout bridge can drain and
            // the proxy process can exit when the SSH session closes.
            _ = shutdown(socketFD, 1)
            group.leave()
        }

        // Socket -> Stdout
        DispatchQueue.global().async {
            bridgeFileDescriptors(from: socketFD, to: 1)
            group.leave()
        }

        group.wait()
        _ = systemClose(socketFD)
    }

    private static func bridgeFileDescriptors(from sourceFD: Int32, to destFD: Int32) {
        let bufferSize = 4096
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 1)
        defer { buffer.deallocate() }

        while true {
            let count = socketRead(fileDesc: sourceFD, buffer: buffer, count: bufferSize)
            if count <= 0 { break }
            // A single write() can satisfy only part of the buffer. Dropping the
            // remainder truncates a length-prefixed RPC frame and desynchronizes
            // the bridge permanently, so loop until every byte is delivered.
            guard socketWriteAll(fileDesc: destFD, buffer: buffer, count: count) else { break }
        }
    }

    private static func startDaemon(pidFile: String, socketPath: String) {
        let binaryPath = CommandLine.arguments[0]
        let serverDir = (pidFile as NSString).deletingLastPathComponent
        let stderrLogPath = "\(serverDir)/daemon.stderr.log"

        // Truncate stderr log if it's grown beyond 10 MB so it can't fill the disk
        if let attrs = try? FileManager.default.attributesOfItem(atPath: stderrLogPath),
           let size = attrs[.size] as? UInt64, size > 10 * 1024 * 1024 {
            try? "".write(toFile: stderrLogPath, atomically: true, encoding: .utf8)
        }

        let process = Process()
        #if os(Linux)
        // Use setsid to start daemon in a new session on Linux. This keeps
        // the daemon alive when the proxy/SSH process exits.
        process.executableURL = URL(fileURLWithPath: "/usr/bin/setsid")
        process.arguments = [
            "--fork",  // Fork and exit parent immediately
            binaryPath,
            "run",
            "--pid-file", pidFile,
            "--stdin-socket", socketPath,
            "--stdout-socket", socketPath,
            "--stderr-socket", stderrLogPath
        ]
        #else
        // macOS does not provide /usr/bin/setsid. Launch the daemon directly
        // with detached stdio; once spawned it will survive proxy exit.
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = [
            "run",
            "--pid-file", pidFile,
            "--stdin-socket", socketPath,
            "--stdout-socket", socketPath,
            "--stderr-socket", stderrLogPath
        ]
        #endif

        // stdout goes to /dev/null (would corrupt RPC protocol).
        // stderr goes to a log file so daemon panics/errors leave a trace.
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let stderrFD = open(stderrLogPath, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        if stderrFD >= 0 {
            process.standardError = FileHandle(fileDescriptor: stderrFD, closeOnDealloc: true)
        } else {
            process.standardError = FileHandle.nullDevice
        }

        do {
            try process.run()
            // Do not wait for the daemon. Waiting can hang with GCD/libdispatch;
            // the proxy polls the socket below to confirm startup.
            usleep(100_000) // 100ms
        } catch {
            fputs("Failed to spawn daemon: \(error)\n", stderr)
        }
    }
}

import Foundation

enum Proxy {
    static func start(reconnect: Bool) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let serverDir = "\(home)/.redmargin-server"
        let socketPath = "\(serverDir)/rpc.sock"
        let pidFile = "\(serverDir)/daemon.pid"
        
        // 1. Ensure directory exists
        try? FileManager.default.createDirectory(atPath: serverDir, withIntermediateDirectories: true)
        
        // 2. Try to connect to Daemon
        var fd = UnixSocketClient.connect(path: socketPath)
        
        if fd < 0 {
            // Check if daemon is running
            if !isDaemonRunning(pidFile: pidFile) {
                print("Daemon not running, starting...")
                startDaemon(pidFile: pidFile, socketPath: socketPath)
                
                // Wait for socket to be created (max 2 seconds)
                for _ in 1...20 {
                    Thread.sleep(forTimeInterval: 0.1)
                    fd = UnixSocketClient.connect(path: socketPath)
                    if fd >= 0 { break }
                }
            }
        }
        
        if fd < 0 {
            print("Failed to connect to daemon at \(socketPath)")
            exit(1)
        }
        
        let socketFD = fd
        
        // 3. Bridge
        let group = DispatchGroup()
        group.enter()
        group.enter()
        
        // Stdin -> Socket
        DispatchQueue.global().async {
            let bufferSize = 4096
            let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 1)
            defer { buffer.deallocate() }
            
            while true {
                let count = socket_read(fd: 0, buffer: buffer, count: bufferSize)
                if count <= 0 { break }
                
                let written = socket_write(fd: socketFD, buffer: buffer, count: count)
                if written < 0 { break }
            }
            group.leave()
        }
        
        // Socket -> Stdout
        DispatchQueue.global().async {
            let bufferSize = 4096
            let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 1)
            defer { buffer.deallocate() }
            
            while true {
                let count = socket_read(fd: socketFD, buffer: buffer, count: bufferSize)
                if count <= 0 { break }
                
                let written = socket_write(fd: 1, buffer: buffer, count: count)
                if written < 0 { break }
            }
            group.leave()
        }
        
        group.wait()
        
        if socketFD >= 0 {
            _ = system_close(socketFD)
        }
    }
    
    private static func isDaemonRunning(pidFile: String) -> Bool {
        guard let pidString = try? String(contentsOfFile: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int32(pidString) else {
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
        
        do {
            try process.run()
            // Daemon mode forks and parent exits immediately
            process.waitUntilExit()
        } catch {
            print("Failed to spawn daemon: \(error)")
        }
    }
}

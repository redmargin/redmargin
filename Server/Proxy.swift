import Foundation

enum Proxy {
    static func start(reconnect: Bool) {
        // TODO: Resolve path dynamically, for now assume standard
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let socketPath = "\(home)/.redmargin-server/rpc.sock"
        
        // 1. Connect to Daemon
        let fd = UnixSocketClient.connect(path: socketPath)
        
        if fd < 0 {
            if reconnect {
                // Try to spawn daemon?
                // For now just fail
                print("Failed to connect to daemon at \(socketPath)")
                exit(1)
            } else {
                exit(1)
            }
        }
        
        // 2. Bridge
        let group = DispatchGroup()
        group.enter()
        group.enter()
        
        // Stdin -> Socket
        DispatchQueue.global().async {
            let bufferSize = 4096
            let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 1)
            defer { buffer.deallocate() }
            
            while true {
                // Read from STDIN_FILENO (0)
                let count = socket_read(fd: 0, buffer: buffer, count: bufferSize)
                if count <= 0 { break }
                
                let written = socket_write(fd: fd, buffer: buffer, count: count)
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
                let count = socket_read(fd: fd, buffer: buffer, count: bufferSize)
                if count <= 0 { break }
                
                // Write to STDOUT_FILENO (1)
                let written = socket_write(fd: 1, buffer: buffer, count: count)
                if written < 0 { break }
            }
            group.leave()
        }
        
        group.wait()
        
        // Close socket
        if fd >= 0 {
            let _ = system_close(fd)
        }
    }
}
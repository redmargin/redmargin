import Foundation

#if canImport(Glibc)
import Glibc
let system_socket = Glibc.socket
let system_bind = Glibc.bind
let system_listen = Glibc.listen
let system_accept = Glibc.accept
let system_close = Glibc.close
let system_unlink = Glibc.unlink
let system_read = Glibc.read
let system_write = Glibc.write
let system_connect = Glibc.connect
typealias SocketLen = socklen_t
#elseif canImport(Darwin)
import Darwin
let system_socket = Darwin.socket
let system_bind = Darwin.bind
let system_listen = Darwin.listen
let system_accept = Darwin.accept
let system_close = Darwin.close
let system_unlink = Darwin.unlink
let system_read = Darwin.read
let system_write = Darwin.write
let system_connect = Darwin.connect
typealias SocketLen = socklen_t
#endif

func socket_read(fd: Int32, buffer: UnsafeMutableRawPointer, count: Int) -> Int {
    return system_read(fd, buffer, count)
}

func socket_write(fd: Int32, buffer: UnsafeRawPointer, count: Int) -> Int {
    return system_write(fd, buffer, count)
}

class UnixSocketListener {
    let path: String
    private var fd: Int32 = -1
    
    init(path: String) {
        self.path = path
    }
    
    func start() throws {
        // Remove existing socket file
        _ = system_unlink(path)
        
        #if os(Linux)
        let socketType = Int32(SOCK_STREAM.rawValue)
        #else
        let socketType = SOCK_STREAM
        #endif
        
        fd = system_socket(AF_UNIX, socketType, 0)
        guard fd >= 0 else {
            throw NSError(domain: "UnixSocket", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create socket"])
        }
        
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        
        // Handle path copy safely
        let pathLen = path.utf8.count
        guard pathLen < 104 else { // standard limit
            throw NSError(domain: "UnixSocket", code: 2, userInfo: [NSLocalizedDescriptionKey: "Socket path too long"])
        }
        
        let _ = withUnsafeMutablePointer(to: &addr.sun_path) { sunPath in
            path.withCString { pathPtr in
                strncpy(sunPath, pathPtr, 104)
            }
        }
        
        #if os(macOS)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        #endif
        
        let addrSize = SocketLen(MemoryLayout<sockaddr_un>.size)
        
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                system_bind(fd, saPtr, addrSize)
            }
        }
        
        guard bindResult == 0 else {
            _ = system_close(fd)
            throw NSError(domain: "UnixSocket", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to bind socket: \(errno)"])
        }
        
        guard system_listen(fd, 5) == 0 else {
            _ = system_close(fd)
            throw NSError(domain: "UnixSocket", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to listen"])
        }
        
        fputs("Listening on \(path)\n", stderr)
    }
    
    func acceptConnection() -> Int32 {
        var clientAddr = sockaddr_un()
        var clientAddrLen = SocketLen(MemoryLayout<sockaddr_un>.size)
        
        let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                system_accept(fd, saPtr, &clientAddrLen)
            }
        }
        
        return clientFD
    }
    
    func close() {
        if fd >= 0 {
            _ = system_close(fd)
            fd = -1
        }
        _ = system_unlink(path)
    }
}

class UnixSocketClient {
    static func connect(path: String) -> Int32 {
        #if os(Linux)
        let socketType = Int32(SOCK_STREAM.rawValue)
        #else
        let socketType = SOCK_STREAM
        #endif
        
        let fd = system_socket(AF_UNIX, socketType, 0)
        guard fd >= 0 else { return -1 }
        
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        
        let pathLen = path.utf8.count
        guard pathLen < 104 else {
            _ = system_close(fd)
            return -1
        }
        
        let _ = withUnsafeMutablePointer(to: &addr.sun_path) { sunPath in
            path.withCString { pathPtr in
                strncpy(sunPath, pathPtr, 104)
            }
        }
        
        #if os(macOS)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        #endif
        
        let addrSize = SocketLen(MemoryLayout<sockaddr_un>.size)
        
        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                system_connect(fd, saPtr, addrSize)
            }
        }
        
        if result == 0 {
            return fd
        } else {
            _ = system_close(fd)
            return -1
        }
    }
}


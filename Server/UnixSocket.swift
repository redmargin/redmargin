import Foundation

#if canImport(Glibc)
import Glibc
let systemSocket = Glibc.socket
let systemBind = Glibc.bind
let systemListen = Glibc.listen
let systemAccept = Glibc.accept
let systemClose = Glibc.close
let systemUnlink = Glibc.unlink
let systemRead = Glibc.read
let systemWrite = Glibc.write
let systemConnect = Glibc.connect
typealias SocketLen = socklen_t
#elseif canImport(Darwin)
import Darwin
let systemSocket = Darwin.socket
let systemBind = Darwin.bind
let systemListen = Darwin.listen
let systemAccept = Darwin.accept
let systemClose = Darwin.close
let systemUnlink = Darwin.unlink
let systemRead = Darwin.read
let systemWrite = Darwin.write
let systemConnect = Darwin.connect
typealias SocketLen = socklen_t
#endif

func socketRead(fileDesc: Int32, buffer: UnsafeMutableRawPointer, count: Int) -> Int {
    return systemRead(fileDesc, buffer, count)
}

/// The RPC socket is unauthenticated: whoever reaches it drives file operations
/// as the account running the daemon. Socket and directory modes are the primary
/// defence; this is the second one, used to reject a peer running as anyone else.
/// Returns nil on platforms that do not expose peer credentials, where the caller
/// falls back to the filesystem modes alone.
func socketPeerUID(fileDesc: Int32) -> uid_t? {
    #if canImport(Darwin)
    var uid = uid_t()
    var gid = gid_t()
    return getpeereid(fileDesc, &uid, &gid) == 0 ? uid : nil
    #elseif canImport(Glibc)
    var credentials = PeerCredentials()
    var length = SocketLen(MemoryLayout<PeerCredentials>.size)
    let succeeded = withUnsafeMutablePointer(to: &credentials) { pointer in
        getsockopt(fileDesc, SOL_SOCKET, SO_PEERCRED, pointer, &length) == 0
    }
    return succeeded ? credentials.uid : nil
    #else
    return nil
    #endif
}

#if canImport(Glibc)
/// Mirrors `struct ucred`, which Swift's Glibc overlay does not re-export. The
/// layout is fixed by the kernel ABI that SO_PEERCRED fills in.
private struct PeerCredentials {
    var pid: pid_t = 0
    var uid: uid_t = 0
    var gid: gid_t = 0
}
#endif

func socketWrite(fileDesc: Int32, buffer: UnsafeRawPointer, count: Int) -> Int {
    return systemWrite(fileDesc, buffer, count)
}

/// Writes the whole buffer, looping until every byte is sent. A single write()
/// can short-write on a full send buffer (a large git diff or base64 asset);
/// dropping the remainder truncates the length-prefixed frame and desyncs the
/// client's stream permanently. Returns false if the socket is closed or errors.
///
/// A peer that disappears mid-write yields EPIPE rather than a fatal SIGPIPE
/// (suppressed at startup in main.swift), and surfaces here as `false` so the
/// caller stops sending to that client.
func socketWriteAll(fileDesc: Int32, buffer: UnsafeRawPointer, count: Int) -> Bool {
    var offset = 0
    while offset < count {
        let n = systemWrite(fileDesc, buffer + offset, count - offset)
        if n > 0 {
            offset += n
            continue
        }
        if n < 0 && (errno == EINTR || errno == EAGAIN) {
            continue
        }
        return false
    }
    return true
}

class UnixSocketListener {
    let path: String
    private var fileDescriptor: Int32 = -1

    init(path: String) {
        self.path = path
    }

    func start() throws {
        // Remove existing socket file
        _ = systemUnlink(path)

        #if os(Linux)
        let socketType = Int32(SOCK_STREAM.rawValue)
        #else
        let socketType = SOCK_STREAM
        #endif

        fileDescriptor = systemSocket(AF_UNIX, socketType, 0)
        guard fileDescriptor >= 0 else {
            let msg = "Failed to create socket"
            throw NSError(domain: "UnixSocket", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        // Handle path copy safely
        let pathLen = path.utf8.count
        guard pathLen < 104 else { // standard limit
            throw NSError(domain: "UnixSocket", code: 2, userInfo: [NSLocalizedDescriptionKey: "Socket path too long"])
        }

        _ = withUnsafeMutablePointer(to: &addr.sun_path) { sunPath in
            path.withCString { pathPtr in
                strncpy(sunPath, pathPtr, 104)
            }
        }

        #if os(macOS)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        #endif

        let addrSize = SocketLen(MemoryLayout<sockaddr_un>.size)

        // bind() creates the socket file with 0666 masked by the login umask. On a
        // group- or world-writable umask that hands any local user an unauthenticated
        // RPC channel into this account, so create it 0600 and confirm afterwards.
        let previousMask = umask(0o177)
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                systemBind(fileDescriptor, saPtr, addrSize)
            }
        }
        _ = umask(previousMask)

        guard bindResult == 0 else {
            _ = systemClose(fileDescriptor)
            let msg = "Failed to bind socket: \(errno)"
            throw NSError(domain: "UnixSocket", code: 3, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        // Fail closed: an unrestricted socket must never be left listening.
        guard chmod(path, 0o600) == 0 else {
            _ = systemClose(fileDescriptor)
            _ = systemUnlink(path)
            let msg = "Failed to restrict socket permissions: \(errno)"
            throw NSError(domain: "UnixSocket", code: 5, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        guard systemListen(fileDescriptor, 5) == 0 else {
            _ = systemClose(fileDescriptor)
            throw NSError(domain: "UnixSocket", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to listen"])
        }

        fputs("Listening on \(path)\n", stderr)
    }

    func acceptConnection() -> Int32 {
        var clientAddr = sockaddr_un()
        var clientAddrLen = SocketLen(MemoryLayout<sockaddr_un>.size)

        let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                systemAccept(fileDescriptor, saPtr, &clientAddrLen)
            }
        }

        return clientFD
    }

    func close() {
        if fileDescriptor >= 0 {
            _ = systemClose(fileDescriptor)
            fileDescriptor = -1
        }
        _ = systemUnlink(path)
    }
}

class UnixSocketClient {
    static func connect(path: String) -> Int32 {
        #if os(Linux)
        let socketType = Int32(SOCK_STREAM.rawValue)
        #else
        let socketType = SOCK_STREAM
        #endif

        let sockFD = systemSocket(AF_UNIX, socketType, 0)
        guard sockFD >= 0 else { return -1 }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathLen = path.utf8.count
        guard pathLen < 104 else {
            _ = systemClose(sockFD)
            return -1
        }

        _ = withUnsafeMutablePointer(to: &addr.sun_path) { sunPath in
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
                systemConnect(sockFD, saPtr, addrSize)
            }
        }

        if result == 0 {
            return sockFD
        } else {
            _ = systemClose(sockFD)
            return -1
        }
    }
}

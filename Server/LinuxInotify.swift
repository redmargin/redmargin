import Foundation

#if os(Linux)
import Glibc

let IN_MODIFY: UInt32 = 0x00000002
let IN_DELETE_SELF: UInt32 = 0x00000400
let IN_MOVE_SELF: UInt32 = 0x00000800

struct InotifyEventRaw {
    var wd: Int32
    var mask: UInt32
    var cookie: UInt32
    var len: UInt32
}

class LinuxInotify {
    private var fd: Int32 = -1
    private let eventSize = MemoryLayout<InotifyEventRaw>.size
    
    init() throws {
        fd = inotify_init()
        if fd < 0 {
            throw NSError(domain: "Inotify", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to init inotify"])
        }
        
        // Set non-blocking
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
    }
    
    deinit {
        if fd >= 0 {
            close(fd)
        }
    }
    
    func addWatch(path: String, mask: UInt32) throws -> Int32 {
        let wd = inotify_add_watch(fd, path, mask)
        if wd < 0 {
            throw NSError(domain: "Inotify", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to add watch"])
        }
        return wd
    }
    
    func removeWatch(wd: Int32) {
        inotify_rm_watch(fd, wd)
    }
    
    func readEvents() -> [UInt32] {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let n = read(fd, &buffer, 4096)
        
        if n <= 0 { return [] }
        
        var events: [UInt32] = []
        var i = 0
        while i < n {
            if i + eventSize > n { break }
            
            let event = buffer.withUnsafeBytes { ptr -> InotifyEventRaw in
                return ptr.load(fromByteOffset: i, as: InotifyEventRaw.self)
            }
            
            events.append(event.mask)
            
            i += eventSize + Int(event.len)
        }
        
        return events
    }
    
    var fileDescriptor: Int32 {
        return fd
    }
}
#endif
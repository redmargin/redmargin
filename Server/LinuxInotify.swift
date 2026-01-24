import Foundation

#if os(Linux)
import Glibc

// swiftlint:disable identifier_name
let IN_MODIFY: UInt32 = 0x00000002
let IN_DELETE_SELF: UInt32 = 0x00000400
let IN_MOVE_SELF: UInt32 = 0x00000800
// swiftlint:enable identifier_name

struct InotifyEventRaw {
    var wd: Int32  // swiftlint:disable:this identifier_name
    var mask: UInt32
    var cookie: UInt32
    var len: UInt32
}

class LinuxInotify {
    private var fileDesc: Int32 = -1
    private let eventSize = MemoryLayout<InotifyEventRaw>.size

    init() throws {
        fileDesc = inotify_init()
        if fileDesc < 0 {
            throw NSError(domain: "Inotify", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to init inotify"])
        }

        // Set non-blocking
        let flags = fcntl(fileDesc, F_GETFL)
        _ = fcntl(fileDesc, F_SETFL, flags | O_NONBLOCK)
    }

    deinit {
        if fileDesc >= 0 {
            close(fileDesc)
        }
    }

    func addWatch(path: String, mask: UInt32) throws -> Int32 {
        let watchDesc = inotify_add_watch(fileDesc, path, mask)
        if watchDesc < 0 {
            throw NSError(domain: "Inotify", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to add watch"])
        }
        return watchDesc
    }

    func removeWatch(watchDesc: Int32) {
        inotify_rm_watch(fileDesc, watchDesc)
    }

    func readEvents() -> [UInt32] {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = read(fileDesc, &buffer, 4096)

        if bytesRead <= 0 { return [] }

        var events: [UInt32] = []
        var offset = 0
        while offset < bytesRead {
            if offset + eventSize > bytesRead { break }

            let event = buffer.withUnsafeBytes { ptr -> InotifyEventRaw in
                return ptr.load(fromByteOffset: offset, as: InotifyEventRaw.self)
            }

            events.append(event.mask)

            offset += eventSize + Int(event.len)
        }

        return events
    }

    var fileDescriptor: Int32 {
        return fileDesc
    }
}
#endif

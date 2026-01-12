import Foundation

class FileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let url: URL
    private let onChange: () -> Void
    private let eventMask: DispatchSource.FileSystemEvent

    init?(url: URL, writeOnly: Bool = false, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        // writeOnly excludes .attrib to avoid loops when file is read (atime updates)
        self.eventMask = writeOnly ? [.write, .rename, .delete] : [.write, .rename, .delete, .attrib]
        guard startWatching() else {
            print("[FileWatcher] Failed to start watching: \(url.path)")
            return nil
        }
        print("[FileWatcher] Started watching: \(url.path)")
    }

    private func startWatching() -> Bool {
        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            print("[FileWatcher] Failed to open: \(url.path)")
            return false
        }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: eventMask,
            queue: .main
        )

        source?.setEventHandler { [weak self] in
            guard let self = self else { return }
            let events = self.source?.data ?? []
            print("[FileWatcher] Event on \(self.url.lastPathComponent): \(events)")

            // For rename/delete (atomic writes), restart the watcher
            if events.contains(.rename) || events.contains(.delete) {
                self.restartWatching()
            } else {
                self.onChange()
            }
        }

        // Don't close fd in cancel handler - we manage it explicitly
        source?.setCancelHandler { }

        source?.resume()
        return true
    }

    private func restartWatching() {
        // Cancel old source and close old fd BEFORE opening new one
        source?.cancel()
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }

        // Delay to let file system settle after atomic write
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            if self.startWatching() {
                print("[FileWatcher] Restarted watching: \(self.url.path)")
                self.onChange()
            } else {
                print("[FileWatcher] Failed to restart watching: \(self.url.path)")
            }
        }
    }

    deinit {
        source?.cancel()
        if fileDescriptor >= 0 {
            close(fileDescriptor)
        }
    }
}

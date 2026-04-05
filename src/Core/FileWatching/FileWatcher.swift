import Foundation
#if canImport(AppKit)
import AppKit
#endif

#if os(macOS)
public class FileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let url: URL
    private let onChange: () -> Void
    private let eventMask: DispatchSource.FileSystemEvent
    private var isRecreating = false
    private var wakeObserver: Any?

    /// Called when all retry attempts are exhausted and the watcher is dead.
    public var onWatcherDied: (() -> Void)?

    public init?(url: URL, writeOnly: Bool = false, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        // writeOnly excludes .attrib to avoid loops when file is read (atime updates)
        self.eventMask = writeOnly ? [.write, .rename, .delete] : [.write, .rename, .delete, .attrib]
        guard startWatching() else {
            print("[FileWatcher] Failed to start watching: \(url.path)")
            return nil
        }
        print("[FileWatcher] Started watching: \(url.path)")

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.recreateAfterWake()
        }
    }

    private func recreateAfterWake() {
        guard !isRecreating else { return }
        isRecreating = true
        print("[FileWatcher] System wake: recreating watcher for \(url.lastPathComponent)")

        // Tear down old dispatch source and file descriptor
        source?.cancel()
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }

        if startWatching() {
            print("[FileWatcher] Wake recreation succeeded for \(url.lastPathComponent)")
            isRecreating = false
            // Fire onChange to pick up any changes during sleep
            onChange()
        } else {
            isRecreating = false
            retryStartWatching(attempt: 1)
        }
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

        retryStartWatching(attempt: 1)
    }

    private static let maxRetries = 5
    private static let retryDelays: [Double] = [0.1, 0.2, 0.5, 1.0, 2.0]

    private func retryStartWatching(attempt: Int) {
        let delay = FileWatcher.retryDelays[min(attempt - 1, FileWatcher.retryDelays.count - 1)]

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            if self.startWatching() {
                print("[FileWatcher] Restarted watching (attempt \(attempt)): \(self.url.path)")
                self.onChange()
            } else if attempt < FileWatcher.maxRetries {
                print("[FileWatcher] Retry \(attempt)/\(FileWatcher.maxRetries) failed, retrying: \(self.url.path)")
                self.retryStartWatching(attempt: attempt + 1)
            } else {
                print("[FileWatcher] Failed to restart after \(FileWatcher.maxRetries) attempts: \(self.url.path)")
                self.onWatcherDied?()
            }
        }
    }

    deinit {
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        source?.cancel()
        if fileDescriptor >= 0 {
            close(fileDescriptor)
        }
    }
}
#endif

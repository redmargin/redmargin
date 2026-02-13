import Foundation
import RedmarginCore

protocol ServerWatcher {
    init?(path: String, onChange: @escaping () -> Void)
    func stop()
}

#if os(macOS)
typealias PlatformWatcher = DarwinWatcher

class DarwinWatcher: ServerWatcher {
    private var internalWatcher: FileWatcher?

    required init?(path: String, onChange: @escaping () -> Void) {
        let url = URL(fileURLWithPath: path)
        self.internalWatcher = FileWatcher(url: url, onChange: onChange)
        if self.internalWatcher == nil { return nil }
    }

    func stop() {
        internalWatcher = nil
    }
}
#elseif os(Linux)
import Glibc
typealias PlatformWatcher = LinuxWatcher

class LinuxWatcher: ServerWatcher {
    private var inotify: LinuxInotify?
    private var source: DispatchSourceRead?
    private let path: String
    private let onChange: () -> Void

    private static let maxRetries = 5
    private static let retryDelays: [Double] = [0.1, 0.2, 0.5, 1.0, 2.0]

    required init?(path: String, onChange: @escaping () -> Void) {
        self.path = path
        self.onChange = onChange

        guard startWatching() else {
            print("[LinuxFileWatcher] Failed to start: \(path)")
            return nil
        }
        print("[LinuxFileWatcher] Started watching: \(path)")
    }

    private func startWatching() -> Bool {
        do {
            let inotify = try LinuxInotify()
            self.inotify = inotify

            let mask = IN_MODIFY | IN_DELETE_SELF | IN_MOVE_SELF
            _ = try inotify.addWatch(path: path, mask: mask)

            let source = DispatchSource.makeReadSource(fileDescriptor: inotify.fileDescriptor, queue: .global())
            source.setEventHandler { [weak self] in
                self?.handleInotifyEvents()
            }
            source.resume()
            self.source = source
            return true
        } catch {
            return false
        }
    }

    private func handleInotifyEvents() {
        let events = inotify?.readEvents() ?? []
        guard !events.isEmpty else { return }

        let needsRestart = events.contains { mask in
            (mask & IN_DELETE_SELF) != 0 || (mask & IN_MOVE_SELF) != 0
        }

        if needsRestart {
            restartWatching()
        } else {
            onChange()
        }
    }

    private func restartWatching() {
        // Tear down old watch
        source?.cancel()
        source = nil
        inotify = nil

        retryStartWatching(attempt: 1)
    }

    private func retryStartWatching(attempt: Int) {
        let delay = LinuxWatcher.retryDelays[min(attempt - 1, LinuxWatcher.retryDelays.count - 1)]

        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            if self.startWatching() {
                print("[LinuxFileWatcher] Restarted watching (attempt \(attempt)): \(self.path)")
                self.onChange()
            } else if attempt < LinuxWatcher.maxRetries {
                print("[LinuxFileWatcher] Retry \(attempt)/\(LinuxWatcher.maxRetries) failed, retrying: \(self.path)")
                self.retryStartWatching(attempt: attempt + 1)
            } else {
                print("[LinuxFileWatcher] Failed to restart after \(LinuxWatcher.maxRetries) attempts: \(self.path)")
            }
        }
    }

    func stop() {
        source?.cancel()
        source = nil
        inotify = nil
    }
}
#endif

// MARK: - Directory Watchers

protocol ServerDirectoryWatcher {
    init?(rootPath: String, ignoredDirs: Set<String>, onChange: @escaping () -> Void)
    func stop()
}

#if os(macOS)
typealias PlatformDirectoryWatcher = DarwinDirectoryWatcher

class DarwinDirectoryWatcher: ServerDirectoryWatcher {
    private var internalWatcher: FileWatcher?

    required init?(rootPath: String, ignoredDirs: Set<String>, onChange: @escaping () -> Void) {
        let url = URL(fileURLWithPath: rootPath)
        self.internalWatcher = FileWatcher(url: url, writeOnly: true, onChange: onChange)
        guard self.internalWatcher != nil else { return nil }
    }

    func stop() {
        internalWatcher = nil
    }
}
#elseif os(Linux)
typealias PlatformDirectoryWatcher = LinuxDirectoryWatcher

class LinuxDirectoryWatcher: ServerDirectoryWatcher {
    private var inotify: LinuxInotify?
    private var source: DispatchSourceRead?
    private let rootPath: String
    private let onChange: () -> Void
    private let ignoredDirs: Set<String>
    private var watchDescriptors: [Int32: String] = [:]
    private var debounceWorkItem: DispatchWorkItem?

    required init?(rootPath: String, ignoredDirs: Set<String>, onChange: @escaping () -> Void) {
        self.rootPath = rootPath
        self.onChange = onChange
        self.ignoredDirs = ignoredDirs

        do {
            let inotify = try LinuxInotify()
            self.inotify = inotify

            addWatchesRecursively(at: rootPath)

            let source = DispatchSource.makeReadSource(
                fileDescriptor: inotify.fileDescriptor, queue: .global()
            )
            source.setEventHandler { [weak self] in
                self?.handleDirectoryEvents()
            }
            source.resume()
            self.source = source

            print("[LinuxDirectoryWatcher] Watching \(watchDescriptors.count) directories under: \(rootPath)")
        } catch {
            print("[LinuxDirectoryWatcher] Failed to start: \(error)")
            return nil
        }
    }

    private func addWatchesRecursively(at path: String) {
        let dirMask = IN_CREATE | IN_DELETE | IN_MOVED_FROM | IN_MOVED_TO
        if let watchDesc = try? inotify?.addWatch(path: path, mask: dirMask) {
            watchDescriptors[watchDesc] = path
        }

        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        while let itemURL = enumerator.nextObject() as? URL {
            let isDir = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                if ignoredDirs.contains(itemURL.lastPathComponent) {
                    enumerator.skipDescendants()
                } else {
                    if let watchDesc = try? inotify?.addWatch(path: itemURL.path, mask: dirMask) {
                        watchDescriptors[watchDesc] = itemURL.path
                    }
                }
            }
        }
    }

    private func handleDirectoryEvents() {
        let events = inotify?.readEvents() ?? []
        if !events.isEmpty {
            debouncedOnChange()
        }
    }

    private func debouncedOnChange() {
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.refreshWatches()
            self.onChange()
        }
        debounceWorkItem = workItem
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    private func refreshWatches() {
        // Remove all existing watches and re-scan
        for watchDesc in watchDescriptors.keys {
            inotify?.removeWatch(watchDesc: watchDesc)
        }
        watchDescriptors.removeAll()
        addWatchesRecursively(at: rootPath)
    }

    func stop() {
        debounceWorkItem?.cancel()
        source?.cancel()
        source = nil
        inotify = nil
        watchDescriptors.removeAll()
    }
}
#endif

// MARK: - Git Watchers

class GitWatcher {
    private let repoRoot: URL
    private let onChange: () -> Void
    private var indexWatcher: ServerWatcher?
    private var headWatcher: ServerWatcher?
    private var refWatcher: ServerWatcher?

    init(repoRoot: String, onChange: @escaping () -> Void) {
        self.repoRoot = URL(fileURLWithPath: repoRoot)
        self.onChange = onChange
        setupWatchers()
    }

    private func setupWatchers() {
        let gitDir = repoRoot.appendingPathComponent(".git")
        let indexURL = gitDir.appendingPathComponent("index")
        let headURL = gitDir.appendingPathComponent("HEAD")

        // Watch index
        indexWatcher = PlatformWatcher(path: indexURL.path, onChange: onChange)

        // Watch HEAD
        headWatcher = PlatformWatcher(path: headURL.path) { [weak self] in
            // HEAD changed (branch switch)
            self?.onChange()
            self?.updateRefWatcher()
        }

        updateRefWatcher()
    }

    private func updateRefWatcher() {
        let headURL = repoRoot.appendingPathComponent(".git/HEAD")
        guard let rawContent = try? String(contentsOf: headURL, encoding: .utf8),
              !rawContent.isEmpty else {
            return
        }
        let headContent = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !headContent.isEmpty else {
            return
        }

        if headContent.hasPrefix("ref: ") {
            let refPath = String(headContent.dropFirst(5))
            let branchRefURL = repoRoot.appendingPathComponent(".git").appendingPathComponent(refPath)

            // Watch the branch ref file (e.g., refs/heads/main)
            refWatcher = PlatformWatcher(path: branchRefURL.path, onChange: onChange)
        } else {
            // Detached HEAD, no specific ref to watch
            refWatcher = nil
        }
    }

    func stop() {
        indexWatcher?.stop()
        headWatcher?.stop()
        refWatcher?.stop()
    }
}

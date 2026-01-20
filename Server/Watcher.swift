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
    
    required init?(path: String, onChange: @escaping () -> Void) {
        self.path = path
        self.onChange = onChange
        
        do {
            let inotify = try LinuxInotify()
            self.inotify = inotify
            
            let mask = IN_MODIFY | IN_DELETE_SELF | IN_MOVE_SELF
            _ = try inotify.addWatch(path: path, mask: mask)
            
            let source = DispatchSource.makeReadSource(fileDescriptor: inotify.fileDescriptor, queue: .global())
            source.setEventHandler { [weak self] in
                guard let self = self else { return }
                let events = self.inotify?.readEvents() ?? []
                if !events.isEmpty {
                    self.onChange()
                }
            }
            source.resume()
            self.source = source
            
            print("[LinuxFileWatcher] Started watching: \(path)")
        } catch {
            print("[LinuxFileWatcher] Failed to start: \(error)")
            return nil
        }
    }
    
    func stop() {
        source?.cancel()
        source = nil
        inotify = nil
    }
}
#endif

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
        guard let headContent = try? String(contentsOf: headURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) else {
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
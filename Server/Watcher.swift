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
        // RedmarginLib.FileWatcher stops on deinit or we can add a stop method there?
        // It relies on deinit/cancel.
        internalWatcher = nil
    }
}
#elseif os(Linux)
typealias PlatformWatcher = LinuxWatcher
#endif

class LinuxWatcher: ServerWatcher {
    required init?(path: String, onChange: @escaping () -> Void) {
        // TODO: Implement Inotify
        print("LinuxWatcher not implemented yet")
        return nil
    }
    
    func stop() {
    }
}

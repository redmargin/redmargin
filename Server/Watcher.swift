import Foundation
import RedmarginLib

protocol ServerWatcher {
    init?(path: String, onChange: @escaping () -> Void)
    func stop()
}

#if os(macOS)
typealias PlatformWatcher = DarwinWatcher
#elseif os(Linux)
typealias PlatformWatcher = LinuxWatcher
#endif

class DarwinWatcher: ServerWatcher {
    private var internalWatcher: RedmarginLib.FileWatcher?
    
    required init?(path: String, onChange: @escaping () -> Void) {
        let url = URL(fileURLWithPath: path)
        self.internalWatcher = RedmarginLib.FileWatcher(url: url, onChange: onChange)
        if self.internalWatcher == nil { return nil }
    }
    
    func stop() {
        // RedmarginLib.FileWatcher stops on deinit or we can add a stop method there?
        // It relies on deinit/cancel.
        internalWatcher = nil
    }
}

class LinuxWatcher: ServerWatcher {
    required init?(path: String, onChange: @escaping () -> Void) {
        // TODO: Implement Inotify
        print("LinuxWatcher not implemented yet")
        return nil
    }
    
    func stop() {
    }
}

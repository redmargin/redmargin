import Foundation
import RedmarginCore

actor FileOperations {
    
    private var eventHandler: ((Data) -> Void)?
    
    func setEventHandler(_ handler: @escaping (Data) -> Void) {
        self.eventHandler = handler
    }
    
    func listDirectory(path: String) -> ListDirectoryResponsePayload {
        do {
            let expandedPath = NSString(string: path).expandingTildeInPath
            let url = URL(fileURLWithPath: expandedPath)
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )

            let entries: [DirectoryEntry] = contents.compactMap { itemURL in
                let resourceValues = try? itemURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                let isDirectory = resourceValues?.isDirectory ?? false
                let size = resourceValues?.fileSize.map { Int64($0) }
                return DirectoryEntry(name: itemURL.lastPathComponent, isDirectory: isDirectory, size: size)
            }.sorted { lhs, rhs in
                // Directories first, then alphabetically
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

            return ListDirectoryResponsePayload(entries: entries, error: nil)
        } catch {
            return ListDirectoryResponsePayload(entries: nil, error: error.localizedDescription)
        }
    }

    func readFile(path: String) -> ReadFileResponsePayload {
        do {
            let url = URL(fileURLWithPath: path)
            let content = try String(contentsOf: url, encoding: .utf8)
            return ReadFileResponsePayload(content: content, error: nil)
        } catch {
            return ReadFileResponsePayload(content: nil, error: error.localizedDescription)
        }
    }
    
    func writeFile(path: String, content: String) -> WriteFileResponsePayload {
        do {
            let url = URL(fileURLWithPath: path)
            // Atomically write to temp file then rename
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try content.write(to: tempURL, atomically: true, encoding: .utf8)
            
            // Move/Replace
            // This is a simple implementation, might need more robust handling for permissions
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
            } else {
                try FileManager.default.moveItem(at: tempURL, to: url)
            }
            
            return WriteFileResponsePayload(error: nil)
        } catch {
            return WriteFileResponsePayload(error: error.localizedDescription)
        }
    }

    private var watchers: [String: ServerWatcher] = [:]
    
    func watchFile(path: String) -> String {
        let token = UUID().uuidString
        
        if let watcher = PlatformWatcher(path: path, onChange: { [weak self] in
            Task { [weak self] in
                guard let self = self else { return }
                print("File changed: \(path)")
                
                let payload = FileChangedPayload(path: path, changeType: "modified")
                if let data = try? RPCStreamHandler.encode(id: nil, type: RPCMessageType.fileChanged.rawValue, payload: payload) {
                    await self.eventHandler?(data)
                }
            }
        }) {
            watchers[token] = watcher
        }
        
        return token
    }
    
    func unwatchFile(token: String) -> Bool {
        if let watcher = watchers.removeValue(forKey: token) {
            watcher.stop()
            return true
        }
        return false
    }
}
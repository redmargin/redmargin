import Foundation
import RedmarginCore

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

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
        let url = URL(fileURLWithPath: path)
        let directory = url.deletingLastPathComponent()

        // Write to temp file in SAME directory (required for atomic rename)
        let tempName = ".\(url.lastPathComponent).tmp.\(UUID().uuidString)"
        let tempPath = directory.appendingPathComponent(tempName).path

        do {
            // Write content to temp file
            try content.write(toFile: tempPath, atomically: false, encoding: .utf8)
        } catch {
            return WriteFileResponsePayload(error: "Failed to write temp file: \(error.localizedDescription)")
        }

        // Use POSIX rename() which atomically overwrites destination
        // This is the ONLY safe way to do atomic file replacement
        let result = rename(tempPath, path)
        if result != 0 {
            // Clean up temp file on failure
            unlink(tempPath)
            let errorMsg = String(cString: strerror(errno))
            return WriteFileResponsePayload(error: "rename failed: \(errorMsg)")
        }

        return WriteFileResponsePayload(error: nil)
    }

    private var watchers: [String: ServerWatcher] = [:]

    func watchFile(path: String) -> String {
        let token = UUID().uuidString

        if let watcher = PlatformWatcher(path: path, onChange: { [weak self] in
            Task { [weak self] in
                guard let self = self else { return }
                print("File changed: \(path)")

                let payload = FileChangedPayload(path: path, changeType: "modified")
                let msgType = RPCMessageType.fileChanged.rawValue
                if let data = try? RPCStreamHandler.encode(id: nil, type: msgType, payload: payload) {
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

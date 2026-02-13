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

    func findMarkdownFiles(path: String) -> FindMarkdownFilesResponsePayload {
        let ignoredDirectories: Set<String> = [
            ".git", "node_modules", ".build", "build", "DerivedData",
            ".cache", ".npm", "vendor", "Pods", ".svn", ".hg"
        ]
        let markdownExtensions: Set<String> = ["md", "markdown"]

        let expandedPath = NSString(string: path).expandingTildeInPath
        let rootURL = URL(fileURLWithPath: expandedPath)

        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return FindMarkdownFilesResponsePayload(files: nil, error: "Cannot enumerate directory")
        }

        var files: [String] = []
        let rootPath = rootURL.path
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"

        while let itemURL = enumerator.nextObject() as? URL {
            let resourceValues = try? itemURL.resourceValues(forKeys: [.isDirectoryKey])
            let isDirectory = resourceValues?.isDirectory ?? false

            if isDirectory {
                if ignoredDirectories.contains(itemURL.lastPathComponent) {
                    enumerator.skipDescendants()
                }
            } else {
                let ext = itemURL.pathExtension.lowercased()
                if markdownExtensions.contains(ext) {
                    let fullPath = itemURL.path
                    if fullPath.hasPrefix(rootPrefix) {
                        files.append(String(fullPath.dropFirst(rootPrefix.count)))
                    } else {
                        files.append(fullPath)
                    }
                }
            }
        }

        files.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return FindMarkdownFilesResponsePayload(files: files, error: nil)
    }

    func readFile(path: String) -> ReadFileResponsePayload {
        do {
            let url = URL(fileURLWithPath: path)
            let content = try String(contentsOf: url, encoding: .utf8)
            return ReadFileResponsePayload(content: content, error: nil)
        } catch {
            let nsError = error as NSError
            let errorCode: String?

            // CocoaError.fileReadNoSuchFile is code 260 in NSCocoaErrorDomain
            if nsError.domain == NSCocoaErrorDomain && nsError.code == 260 {
                errorCode = FileErrorCode.fileNotFound.rawValue
            } else if nsError.domain == NSCocoaErrorDomain && nsError.code == 257 {
                // CocoaError.fileReadNoPermission
                errorCode = FileErrorCode.permissionDenied.rawValue
            } else {
                errorCode = nil
            }

            return ReadFileResponsePayload(content: nil, error: error.localizedDescription, errorCode: errorCode)
        }
    }

    func readAsset(path: String) -> ReadAssetResponsePayload {
        let expandedPath = NSString(string: path).expandingTildeInPath
        guard let data = FileManager.default.contents(atPath: expandedPath) else {
            return ReadAssetResponsePayload(data: nil, mimeType: nil, error: "File not found")
        }
        let base64 = data.base64EncodedString()
        let mimeType = mimeTypeForExtension((expandedPath as NSString).pathExtension)
        return ReadAssetResponsePayload(data: base64, mimeType: mimeType, error: nil)
    }

    private func mimeTypeForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "webp": return "image/webp"
        case "ico": return "image/x-icon"
        case "bmp": return "image/bmp"
        case "pdf": return "application/pdf"
        default: return "application/octet-stream"
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

    // MARK: - Directory Watching

    private static let ignoredDirectories: Set<String> = [
        ".git", "node_modules", ".build", "build", "DerivedData",
        ".cache", ".npm", "vendor", "Pods", ".svn", ".hg"
    ]

    private var directoryWatchers: [String: ServerDirectoryWatcher] = [:]

    func watchDirectory(path: String) -> String {
        let token = UUID().uuidString
        let expandedPath = NSString(string: path).expandingTildeInPath

        if let watcher = PlatformDirectoryWatcher(
            rootPath: expandedPath,
            ignoredDirs: Self.ignoredDirectories,
            onChange: { [weak self] in
                Task { [weak self] in
                    guard let self = self else { return }
                    let result = await self.findMarkdownFiles(path: expandedPath)
                    let files = result.files ?? []
                    let payload = DirectoryChangedPayload(path: path, files: files)
                    let msgType = RPCMessageType.directoryChanged.rawValue
                    if let data = try? RPCStreamHandler.encode(id: nil, type: msgType, payload: payload) {
                        await self.eventHandler?(data)
                    }
                }
            }
        ) {
            directoryWatchers[token] = watcher
        }

        return token
    }

    func unwatchDirectory(token: String) -> Bool {
        if let watcher = directoryWatchers.removeValue(forKey: token) {
            watcher.stop()
            return true
        }
        return false
    }
}

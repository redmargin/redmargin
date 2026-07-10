import Foundation
import RedmarginCore

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

actor FileOperations {

    private var eventHandler: ((Data) -> Void)?

    private nonisolated func expandTilde(in path: String) -> String {
        NSString(string: path).expandingTildeInPath
    }

    func setEventHandler(_ handler: @escaping (Data) -> Void) {
        self.eventHandler = handler
    }

    func listDirectory(path: String) -> ListDirectoryResponsePayload {
        do {
            let url = URL(fileURLWithPath: expandTilde(in: path))
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: []
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

        let rootURL = URL(fileURLWithPath: expandTilde(in: path))

        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
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

    /// A document is delivered whole inside one JSON frame, so anything past this
    /// could never reach the client anyway. Reading it would only cost both hosts
    /// the memory first. Sits below `RPCStreamHandler.maxFrameLength` to leave
    /// room for the JSON envelope around the content.
    static let maxDocumentBytes = 32 * 1024 * 1024

    func readFile(path: String) -> ReadFileResponsePayload {
        // Resolve first: the checks below must describe the file we actually open,
        // not a symlink standing in front of it.
        let url = URL(fileURLWithPath: expandTilde(in: path))
            .resolvingSymlinksInPath()
            .standardizedFileURL

        // A stat failure is left to the read below, which reports whether the file
        // is missing or unreadable. Only a successful stat can rule the file out.
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let fileType = attributes[.type] as? FileAttributeType {
            // A FIFO or device node would block this actor for the life of the daemon.
            guard fileType == .typeRegular else {
                return ReadFileResponsePayload(content: nil, error: "Not a regular file")
            }
            if let size = (attributes[.size] as? NSNumber)?.int64Value, size > Self.maxDocumentBytes {
                return ReadFileResponsePayload(content: nil, error: "File exceeds \(Self.maxDocumentBytes) bytes")
            }
        }

        do {
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

    /// Asset paths come out of Markdown, so a document decides what this reads.
    /// Anything above this size would be held whole here, again as base64, and
    /// again in the JSON frame, on both hosts. Matches the client's asset cache
    /// limit, above which an asset would not be retained anyway.
    static let maxAssetBytes = 20 * 1024 * 1024

    func readAsset(path: String) -> ReadAssetResponsePayload {
        // Resolve first: the checks below must describe the file we actually open,
        // not a symlink standing in front of it.
        let resolvedURL = URL(fileURLWithPath: expandTilde(in: path))
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let resolvedPath = resolvedURL.path

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: resolvedPath),
              let fileType = attributes[.type] as? FileAttributeType,
              let size = (attributes[.size] as? NSNumber)?.int64Value else {
            return ReadAssetResponsePayload(data: nil, mimeType: nil, error: "File not found")
        }

        // A FIFO or device node would block this actor for the life of the daemon.
        guard fileType == .typeRegular else {
            return ReadAssetResponsePayload(data: nil, mimeType: nil, error: "Not a regular file")
        }

        guard size <= Self.maxAssetBytes else {
            return ReadAssetResponsePayload(data: nil, mimeType: nil, error: "Asset exceeds \(Self.maxAssetBytes) bytes")
        }

        guard let data = FileManager.default.contents(atPath: resolvedPath) else {
            return ReadAssetResponsePayload(data: nil, mimeType: nil, error: "File not found")
        }

        // The file can grow between the stat and the read.
        guard data.count <= Self.maxAssetBytes else {
            return ReadAssetResponsePayload(data: nil, mimeType: nil, error: "Asset exceeds \(Self.maxAssetBytes) bytes")
        }

        let base64 = data.base64EncodedString()
        let mimeType = mimeTypeForExtension((resolvedPath as NSString).pathExtension)
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
        let expandedPath = expandTilde(in: path)
        let url = URL(fileURLWithPath: expandedPath)
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
        let result = rename(tempPath, expandedPath)
        if result != 0 {
            // Clean up temp file on failure
            unlink(tempPath)
            let errorMsg = String(cString: strerror(errno))
            return WriteFileResponsePayload(error: "rename failed: \(errorMsg)")
        }

        return WriteFileResponsePayload(error: nil)
    }

    private var watchers: [String: ServerWatcher] = [:]
    private var fileWatchPaths: [String: String] = [:]  // token -> path
    private var pathToFileToken: [String: String] = [:]  // path -> token (dedup)

    func watchFile(path: String) -> String {
        let expandedPath = expandTilde(in: path)

        // Remove existing watcher for this path to prevent accumulation
        // across reconnections (old unwatch RPCs may have failed).
        if let existingToken = pathToFileToken[expandedPath] {
            watchers[existingToken]?.stop()
            watchers.removeValue(forKey: existingToken)
            fileWatchPaths.removeValue(forKey: existingToken)
            print("[FileOperations] Replaced existing watcher for \(path)")
        }

        let token = UUID().uuidString
        pathToFileToken[expandedPath] = token
        fileWatchPaths[token] = expandedPath

        if let watcher = PlatformWatcher(path: expandedPath, onChange: { [weak self] in
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
            if let path = fileWatchPaths.removeValue(forKey: token) {
                pathToFileToken.removeValue(forKey: path)
            }
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
    private var dirWatchPaths: [String: String] = [:]  // token -> path
    private var pathToDirToken: [String: String] = [:]  // path -> token (dedup)

    func watchDirectory(path: String) -> String {
        let expandedPath = expandTilde(in: path)

        // Remove existing watcher for this path to prevent accumulation
        if let existingToken = pathToDirToken[expandedPath] {
            directoryWatchers[existingToken]?.stop()
            directoryWatchers.removeValue(forKey: existingToken)
            dirWatchPaths.removeValue(forKey: existingToken)
            print("[FileOperations] Replaced existing directory watcher for \(expandedPath)")
        }

        let token = UUID().uuidString
        pathToDirToken[expandedPath] = token
        dirWatchPaths[token] = expandedPath

        if let watcher = PlatformDirectoryWatcher(
            rootPath: expandedPath,
            ignoredDirs: Self.ignoredDirectories,
            onChange: { [weak self] in
                Task { [weak self] in
                    guard let self = self else { return }
                    // Notify client that this directory changed. Client re-lists
                    // via listDirectory; the server doesn't walk the tree.
                    let payload = DirectoryChangedPayload(path: path, files: [])
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
            if let path = dirWatchPaths.removeValue(forKey: token) {
                pathToDirToken.removeValue(forKey: path)
            }
            watcher.stop()
            return true
        }
        return false
    }

    /// Stops and releases every file and directory watcher (freeing their
    /// inotify FDs). Called on client disconnect so watchers don't accumulate
    /// across reconnects until the daemon hits its descriptor limit.
    func stopAllWatchers() {
        for watcher in watchers.values {
            watcher.stop()
        }
        watchers.removeAll()
        fileWatchPaths.removeAll()
        pathToFileToken.removeAll()

        for watcher in directoryWatchers.values {
            watcher.stop()
        }
        directoryWatchers.removeAll()
        dirWatchPaths.removeAll()
        pathToDirToken.removeAll()
    }
}

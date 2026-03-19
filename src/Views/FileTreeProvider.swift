import Foundation
import CoreServices
import RedmarginCore

/// Represents a node in the file tree (either a folder or a file)
public class FileTreeNode: Identifiable, ObservableObject {
    public let id = UUID()
    public let name: String
    public let url: URL
    public let isDirectory: Bool
    public var depth: Int
    @Published public var children: [FileTreeNode]
    @Published public var isExpanded: Bool {
        didSet {
            if isDirectory {
                onExpandedChange?(url.path, isExpanded)
            }
        }
    }
    public var childrenLoaded: Bool = false

    /// Callback when expansion state changes
    var onExpandedChange: ((String, Bool) -> Void)?

    public init(
        name: String,
        url: URL,
        isDirectory: Bool,
        depth: Int,
        children: [FileTreeNode] = [],
        isExpanded: Bool? = nil
    ) {
        self.name = name
        self.url = url
        self.isDirectory = isDirectory
        self.depth = depth
        self.children = children
        self.childrenLoaded = !children.isEmpty || !isDirectory
        self.isExpanded = isExpanded ?? (depth == 0)  // Root level expanded by default
    }
}

/// Provides a hierarchical tree of Markdown files from a directory for sidebar display.
/// Uses lazy single-level loading — only enumerates one directory at a time.
@MainActor
public class FileTreeProvider: ObservableObject {
    @Published public private(set) var rootNodes: [FileTreeNode] = []
    @Published public private(set) var rootDirectory: URL?
    @Published public private(set) var isLoading = false

    private let currentFileURL: URL?
    private var directoryWatcher: FSEventsDirectoryWatcher?
    private var expandedFolders: Set<String> = []
    private let autoExpandRoot: Bool

    public var showHiddenFiles: Bool = false {
        didSet {
            if oldValue != showHiddenFiles { refresh() }
        }
    }

    /// Callback when expanded folders change (path of root, set of expanded folder paths)
    public var onExpandedFoldersChange: ((String, Set<String>) -> Void)?

    /// Directories to skip when enumerating files
    private nonisolated static let ignoredDirectories: Set<String> = [
        ".git", "node_modules", ".build", "build", "DerivedData",
        ".cache", ".npm", "vendor", "Pods", ".svn", ".hg"
    ]

    /// File extensions to include
    private nonisolated static let markdownExtensions: Set<String> = ["md", "markdown"]

    public init(currentFileURL: URL, expandedFolders: Set<String> = []) {
        self.currentFileURL = currentFileURL
        self.expandedFolders = expandedFolders
        self.autoExpandRoot = true
        Task {
            await loadFiles()
        }
    }

    /// Initialize with a root directory directly, skipping git detection.
    /// Root-level folders start collapsed (only `expandedFolders` are expanded).
    public init(rootDirectory: URL, expandedFolders: Set<String> = []) {
        self.currentFileURL = nil
        self.expandedFolders = expandedFolders
        self.autoExpandRoot = false
        self.rootDirectory = rootDirectory
        setupDirectoryWatcher(for: rootDirectory)
        loadRootLevel(from: rootDirectory)
    }

    /// Loads markdown files from the appropriate root directory
    public func loadFiles() async {
        guard let currentFileURL else { return }

        isLoading = true

        // Try to find Git repo root first
        do {
            if let repoRoot = try await GitRepoDetector.detectRepoRoot(forFile: currentFileURL) {
                rootDirectory = repoRoot
                loadRootLevel(from: repoRoot)
                isLoading = false
                setupDirectoryWatcher(for: repoRoot)
                return
            }
        } catch {
            print("[FileTreeProvider] Git detection failed: \(error)")
        }

        // Fall back to file's parent directory
        let parentDir = currentFileURL.deletingLastPathComponent()
        rootDirectory = parentDir
        loadRootLevel(from: parentDir)
        isLoading = false
        setupDirectoryWatcher(for: parentDir)
    }

    /// Refreshes visible levels — root + any expanded directories
    public func refresh() {
        guard let root = rootDirectory else { return }
        print("[FileTreeProvider] refresh() called for \(root.lastPathComponent)")
        reloadVisibleLevels()
    }

    // MARK: - Lazy Loading

    /// Load a single directory's contents (non-recursive)
    private nonisolated func listDirectory(at directory: URL, depth: Int, showHiddenFiles: Bool) -> [FileTreeNode] {
        let resolved = directory.resolvingSymlinksInPath()
        let options: FileManager.DirectoryEnumerationOptions = showHiddenFiles ? [] : [.skipsHiddenFiles]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: resolved,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: options
        ) else {
            return []
        }

        struct Entry {
            let url: URL
            let name: String
            let isDirectory: Bool
        }
        let entries: [Entry] = contents.map { url in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            return Entry(url: url, name: url.lastPathComponent, isDirectory: isDir.boolValue)
        }

        let sorted = entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        var nodes: [FileTreeNode] = []
        for entry in sorted {
            if entry.isDirectory {
                if Self.ignoredDirectories.contains(entry.name) { continue }
                let node = FileTreeNode(
                    name: entry.name,
                    url: entry.url,
                    isDirectory: true,
                    depth: depth,
                    isExpanded: false
                )
                nodes.append(node)
            } else {
                let ext = entry.url.pathExtension.lowercased()
                if Self.markdownExtensions.contains(ext) {
                    let node = FileTreeNode(
                        name: entry.name,
                        url: entry.url,
                        isDirectory: false,
                        depth: depth
                    )
                    nodes.append(node)
                }
            }
        }
        return nodes
    }

    /// Load root level on a background thread
    private func loadRootLevel(from directory: URL) {
        let hidden = showHiddenFiles
        let expanded = expandedFolders
        let autoExpand = autoExpandRoot
        Task.detached { [weak self] in
            guard let self else { return }
            let nodes = self.listDirectory(at: directory, depth: 0, showHiddenFiles: hidden)
            await MainActor.run {
                for node in nodes {
                    self.wireUpNode(node)
                    if node.isDirectory {
                        let shouldExpand = expanded.contains(node.url.path) || autoExpand
                        if shouldExpand {
                            node.isExpanded = shouldExpand
                        }
                    }
                }
                self.rootNodes = nodes
                // Load children for expanded folders
                for node in nodes where node.isDirectory && node.isExpanded {
                    self.loadChildrenIfNeeded(for: node)
                }
            }
        }
    }

    /// Load children for a folder node (single level)
    private func loadChildrenIfNeeded(for node: FileTreeNode) {
        guard node.isDirectory, !node.childrenLoaded else { return }
        node.childrenLoaded = true

        let hidden = showHiddenFiles
        let expanded = expandedFolders
        let url = node.url
        let parentDepth = node.depth

        Task.detached { [weak self] in
            guard let self else { return }
            let children = self.listDirectory(at: url, depth: parentDepth + 1, showHiddenFiles: hidden)
            await MainActor.run {
                for child in children {
                    self.wireUpNode(child)
                    if child.isDirectory {
                        let shouldExpand = expanded.contains(child.url.path)
                        if shouldExpand {
                            child.isExpanded = shouldExpand
                        }
                    }
                }
                node.children = children
                // Recursively load children for any expanded subdirectories
                for child in children where child.isDirectory && child.isExpanded {
                    self.loadChildrenIfNeeded(for: child)
                }
            }
        }
    }

    /// Wire up expansion callback for a node
    private func wireUpNode(_ node: FileTreeNode) {
        node.onExpandedChange = { [weak self] path, expanded in
            self?.handleFolderExpansionChange(path: path, expanded: expanded)
            if expanded {
                // Find the node and load its children
                self?.expandFolder(at: path)
            }
        }
    }

    /// Find a node by path and load its children if needed
    private func expandFolder(at path: String) {
        if let node = findNode(at: path, in: rootNodes) {
            loadChildrenIfNeeded(for: node)
        }
    }

    private func findNode(at path: String, in nodes: [FileTreeNode]) -> FileTreeNode? {
        for node in nodes {
            if node.url.path == path { return node }
            if node.isDirectory, let found = findNode(at: path, in: node.children) {
                return found
            }
        }
        return nil
    }

    // MARK: - Refresh

    /// Reload all visible levels (root + expanded dirs)
    private func reloadVisibleLevels() {
        guard let root = rootDirectory else { return }
        let hidden = showHiddenFiles
        let expanded = expandedFolders
        let autoExpand = autoExpandRoot

        Task.detached { [weak self] in
            guard let self else { return }
            let newRootNodes = self.listDirectory(at: root, depth: 0, showHiddenFiles: hidden)
            await MainActor.run {
                let merged = self.mergeLevel(
                    existing: self.rootNodes,
                    incoming: newRootNodes,
                    depth: 0,
                    expandedFolders: expanded,
                    autoExpandRoot: autoExpand
                )
                self.rootNodes = merged
            }
        }
    }

    /// Merge a single level, preserving existing node identity and loaded children
    private func mergeLevel(
        existing: [FileTreeNode],
        incoming: [FileTreeNode],
        depth: Int,
        expandedFolders: Set<String>,
        autoExpandRoot: Bool
    ) -> [FileTreeNode] {
        var existingByURL: [URL: FileTreeNode] = [:]
        for node in existing {
            existingByURL[node.url] = node
        }

        return incoming.map { newNode in
            if let existingNode = existingByURL[newNode.url] {
                // Reuse existing node for scroll stability
                if existingNode.isDirectory && existingNode.childrenLoaded {
                    // Re-enumerate this level's children if expanded
                    let hidden = self.showHiddenFiles
                    let childNodes = self.listDirectory(at: existingNode.url, depth: depth + 1, showHiddenFiles: hidden)
                    existingNode.children = mergeLevel(
                        existing: existingNode.children,
                        incoming: childNodes,
                        depth: depth + 1,
                        expandedFolders: expandedFolders,
                        autoExpandRoot: false
                    )
                }
                return existingNode
            } else {
                wireUpNode(newNode)
                let shouldExpand = expandedFolders.contains(newNode.url.path)
                    || (autoExpandRoot && depth == 0)
                if shouldExpand && newNode.isDirectory {
                    let callback = newNode.onExpandedChange
                    newNode.onExpandedChange = nil
                    newNode.isExpanded = true
                    newNode.onExpandedChange = callback
                    loadChildrenIfNeeded(for: newNode)
                }
                return newNode
            }
        }
    }

    private func setupDirectoryWatcher(for directory: URL) {
        directoryWatcher = FSEventsDirectoryWatcher(url: directory) { [weak self] in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    private func handleFolderExpansionChange(path: String, expanded: Bool) {
        if expanded {
            expandedFolders.insert(path)
        } else {
            expandedFolders.remove(path)
        }

        // Notify via callback
        if let rootPath = rootDirectory?.path {
            onExpandedFoldersChange?(rootPath, expandedFolders)
        }
    }

    /// Apply expanded folders state to existing nodes
    public func applyExpandedFolders(_ folders: Set<String>) {
        expandedFolders = folders
        applyExpandedStateToNodes(rootNodes)
    }

    private func applyExpandedStateToNodes(_ nodes: [FileTreeNode]) {
        for node in nodes where node.isDirectory {
            let callback = node.onExpandedChange
            node.onExpandedChange = nil
            let shouldExpand = expandedFolders.contains(node.url.path) || (autoExpandRoot && node.depth == 0)
            node.isExpanded = shouldExpand
            node.onExpandedChange = callback

            if shouldExpand {
                loadChildrenIfNeeded(for: node)
            }
            applyExpandedStateToNodes(node.children)
        }
    }
}

/// Watches an entire directory tree recursively using FSEvents.
/// Single kernel-level registration monitors all subdirectories.
/// FSEvents coalesces events within the latency window (built-in debounce).
class FSEventsDirectoryWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: () -> Void

    init?(url: URL, onChange: @escaping () -> Void) {
        self.onChange = onChange
        self.stream = nil

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let paths = [url.path as NSString] as NSArray

        let flags: FSEventStreamCreateFlags =
            UInt32(kFSEventStreamCreateFlagNoDefer) |
            UInt32(kFSEventStreamCreateFlagFileEvents)

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { (_, clientCallBackInfo, _, _, _, _) in
                guard let info = clientCallBackInfo else { return }
                let watcher = Unmanaged<FSEventsDirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
                watcher.onChange()
            },
            &context,
            paths,
            FSEventsGetCurrentEventId(),
            1.0,
            flags
        ) else {
            print("[FSEventsWatcher] Failed to create stream for: \(url.path)")
            return nil
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        let started = FSEventStreamStart(stream)
        print("[FSEventsWatcher] Watching \(url.path) — started: \(started)")

        if !started {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
            return nil
        }
    }

    deinit {
        if let stream = stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            print("[FSEventsWatcher] Stopped watching")
        }
    }
}

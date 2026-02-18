import Foundation
import CoreServices
import RedmarginCore

/// Represents a node in the file tree (either a folder or a file)
public class FileTreeNode: Identifiable, ObservableObject {
    public let id = UUID()
    public let name: String
    public let url: URL
    public let isDirectory: Bool
    public let depth: Int
    @Published public var children: [FileTreeNode]
    @Published public var isExpanded: Bool {
        didSet {
            if isDirectory {
                onExpandedChange?(url.path, isExpanded)
            }
        }
    }

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
        self.isExpanded = isExpanded ?? (depth == 0)  // Root level expanded by default
    }
}

/// Provides a hierarchical tree of Markdown files from a directory for sidebar display.
/// Uses the Git repo root if available, otherwise falls back to the file's parent directory.
@MainActor
public class FileTreeProvider: ObservableObject {
    @Published public private(set) var rootNodes: [FileTreeNode] = []
    @Published public private(set) var rootDirectory: URL?
    @Published public private(set) var isLoading = false

    private let currentFileURL: URL?
    private var directoryWatcher: FSEventsDirectoryWatcher?
    private var expandedFolders: Set<String> = []
    private let autoExpandRoot: Bool

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
        buildTreeAsync(from: rootDirectory)
    }

    /// Loads markdown files from the appropriate root directory
    public func loadFiles() async {
        guard let currentFileURL else { return }

        isLoading = true

        // Try to find Git repo root first
        do {
            if let repoRoot = try await GitRepoDetector.detectRepoRoot(forFile: currentFileURL) {
                rootDirectory = repoRoot
                buildTreeAsync(from: repoRoot)
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
        buildTreeAsync(from: parentDir)
        isLoading = false
        setupDirectoryWatcher(for: parentDir)
    }

    /// Refreshes the file list
    public func refresh() {
        guard let root = rootDirectory else { return }
        print("[FileTreeProvider] refresh() called for \(root.lastPathComponent)")
        buildTreeAsync(from: root)
    }

    private func buildTree(from directory: URL) -> [FileTreeNode] {
        let expanded = expandedFolders
        let autoExpand = autoExpandRoot
        return buildTreeRecursive(at: directory, depth: 0, expandedFolders: expanded, autoExpandRoot: autoExpand)
    }

    /// Builds the tree on a background thread, then applies result on main
    private func buildTreeAsync(from directory: URL) {
        let expanded = expandedFolders
        let autoExpand = autoExpandRoot
        Task.detached { [weak self] in
            guard let self else { return }
            let nodes = self.buildTreeRecursive(
                at: directory,
                depth: 0,
                expandedFolders: expanded,
                autoExpandRoot: autoExpand
            )
            await MainActor.run {
                self.rootNodes = nodes
                self.wireUpCallbacks(nodes)
            }
        }
    }

    /// Wire up expansion callbacks after tree is built (must be on MainActor)
    private func wireUpCallbacks(_ nodes: [FileTreeNode]) {
        for node in nodes where node.isDirectory {
            node.onExpandedChange = { [weak self] path, expanded in
                self?.handleFolderExpansionChange(path: path, expanded: expanded)
            }
            wireUpCallbacks(node.children)
        }
    }

    /// Non-isolated tree builder — runs off the main thread
    private nonisolated func buildTreeRecursive(
        at directory: URL,
        depth: Int,
        expandedFolders: Set<String>,
        autoExpandRoot: Bool
    ) -> [FileTreeNode] {
        var nodes: [FileTreeNode] = []

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        // Pre-compute isDirectory once per entry (uses prefetched values from contentsOfDirectory)
        struct Entry {
            let url: URL
            let name: String
            let isDirectory: Bool
        }
        let entries: [Entry] = contents.map { url in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return Entry(url: url, name: url.lastPathComponent, isDirectory: isDir)
        }

        // Sort: directories first, then alphabetically
        let sorted = entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory  // Directories first
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        for entry in sorted {
            if entry.isDirectory {
                // Skip ignored directories
                if Self.ignoredDirectories.contains(entry.name) {
                    continue
                }

                // Recursively get children
                let children = buildTreeRecursive(
                    at: entry.url,
                    depth: depth + 1,
                    expandedFolders: expandedFolders,
                    autoExpandRoot: autoExpandRoot
                )

                // Only include directory if it has markdown files (directly or nested)
                if !children.isEmpty {
                    let shouldExpand = expandedFolders.contains(entry.url.path) || (autoExpandRoot && depth == 0)
                    let node = FileTreeNode(
                        name: entry.name,
                        url: entry.url,
                        isDirectory: true,
                        depth: depth,
                        children: children,
                        isExpanded: shouldExpand
                    )
                    nodes.append(node)
                }
            } else {
                // Check if it's a markdown file
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
            // Temporarily remove callback to avoid triggering saves
            let callback = node.onExpandedChange
            node.onExpandedChange = nil
            node.isExpanded = expandedFolders.contains(node.url.path) || (autoExpandRoot && node.depth == 0)
            node.onExpandedChange = callback

            // Recursively apply to children
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

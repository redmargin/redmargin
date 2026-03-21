import Foundation
import RedmarginCore

/// Provides a hierarchical tree of files from a remote directory for sidebar display.
/// Uses lazy single-level loading — only enumerates one directory at a time via listDirectory RPC.
@MainActor
public class RemoteFileTreeProvider: ObservableObject {
    @Published public private(set) var rootNodes: [FileTreeNode] = []
    @Published public private(set) var rootDirectory: String?
    @Published public private(set) var isLoading = false

    private let currentFilePath: String
    private let fileProvider: RemoteFileProvider
    private let pathIsDirectory: Bool
    private var expandedFolders: Set<String> = []
    private var directoryWatchToken: WatchToken?
    private var stateObserverTask: Task<Void, Never>?

    /// Callback when expanded folders change (path of root, set of expanded folder paths)
    public var onExpandedFoldersChange: ((String, Set<String>) -> Void)?

    /// Called once rootDirectory is determined to load persisted expanded folders
    private let expandedFoldersLoader: ((String) -> Set<String>)?

    public var showHiddenFiles: Bool = false {
        didSet {
            if oldValue != showHiddenFiles { refresh() }
        }
    }

    /// Directories to skip
    private static let ignoredDirectories: Set<String> = [
        ".git", "node_modules", ".build", "build", "DerivedData",
        ".cache", ".npm", "vendor", "Pods", ".svn", ".hg"
    ]

    /// File extensions to include
    private static let markdownExtensions: Set<String> = ["md", "markdown"]

    public init(
        currentFilePath: String,
        fileProvider: RemoteFileProvider,
        stateChanges: AsyncStream<SSHConnectionState>? = nil,
        expandedFolders: Set<String> = [],
        isDirectory: Bool = false,
        expandedFoldersLoader: ((String) -> Set<String>)? = nil
    ) {
        self.currentFilePath = currentFilePath
        self.fileProvider = fileProvider
        self.pathIsDirectory = isDirectory
        self.expandedFolders = expandedFolders
        self.expandedFoldersLoader = expandedFoldersLoader
        Task {
            await loadFiles()
        }
        if let stateChanges = stateChanges {
            observeConnectionState(stateChanges)
        }
    }

    private func observeConnectionState(_ stateChanges: AsyncStream<SSHConnectionState>) {
        stateObserverTask = Task { [weak self] in
            var previousState: SSHConnectionState?
            for await state in stateChanges {
                guard !Task.isCancelled else { break }
                if previousState == .reconnecting && state == .connected {
                    await self?.loadFiles()
                }
                previousState = state
            }
        }
    }

    /// Loads the root directory
    public func loadFiles() async {
        isLoading = true
        defer { isLoading = false }

        // Try to find Git repo root first
        do {
            if let repoRoot = try await fileProvider.detectGitRepo(for: currentFilePath) {
                rootDirectory = repoRoot
                loadExpandedFoldersFromStorage(rootPath: repoRoot)
                await loadRootLevel(from: repoRoot)
                await setupDirectoryWatching(for: repoRoot)
                return
            }
        } catch {
            print("[RemoteFileTreeProvider] Git detection failed: \(error)")
        }

        // Fall back to the directory itself (if opened as folder) or file's parent
        let fallbackDir = pathIsDirectory
            ? currentFilePath
            : (currentFilePath as NSString).deletingLastPathComponent
        rootDirectory = fallbackDir
        loadExpandedFoldersFromStorage(rootPath: fallbackDir)
        await loadRootLevel(from: fallbackDir)
        await setupDirectoryWatching(for: fallbackDir)
    }

    /// Populate expandedFolders from persisted storage before building the tree
    private func loadExpandedFoldersFromStorage(rootPath: String) {
        if let loader = expandedFoldersLoader {
            let loaded = loader(rootPath)
            if !loaded.isEmpty {
                expandedFolders = loaded
            }
        }
    }

    private func setupDirectoryWatching(for path: String) async {
        if let token = directoryWatchToken {
            await fileProvider.unwatchDirectory(token)
        }

        directoryWatchToken = await fileProvider.watchDirectory(at: path) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    /// Refreshes visible levels — root + any expanded directories
    public func refresh() {
        guard let root = rootDirectory else { return }
        print("[RemoteFileTreeProvider] refresh() for \(root)")

        Task {
            let entries = try? await fileProvider.listDirectory(at: root)
            guard let entries else { return }
            let newNodes = buildNodes(from: entries, parentPath: root, depth: 0)
            rootNodes = mergeLevel(existing: rootNodes, incoming: newNodes, parentPath: root, depth: 0)
        }
    }

    // MARK: - Lazy Loading

    /// Load root level via a single listDirectory call
    private func loadRootLevel(from directory: String) async {
        do {
            let entries = try await fileProvider.listDirectory(at: directory)
            let nodes = buildNodes(from: entries, parentPath: directory, depth: 0)
            for node in nodes {
                wireUpNode(node)
                if node.isDirectory {
                    let shouldExpand = expandedFolders.contains(node.url.path)
                    if shouldExpand {
                        node.isExpanded = true
                    }
                }
            }
            rootNodes = nodes
            // Load children for expanded folders
            for node in nodes where node.isDirectory && node.isExpanded {
                await loadChildrenIfNeeded(for: node)
            }
        } catch {
            print("[RemoteFileTreeProvider] Failed to list root \(directory): \(error)")
        }
    }

    /// Load children for a folder node (single level)
    private func loadChildrenIfNeeded(for node: FileTreeNode) async {
        guard node.isDirectory, !node.childrenLoaded else { return }
        node.childrenLoaded = true

        let path = node.url.path
        let parentDepth = node.depth

        do {
            let entries = try await fileProvider.listDirectory(at: path)
            let children = buildNodes(from: entries, parentPath: path, depth: parentDepth + 1)
            for child in children {
                wireUpNode(child)
                if child.isDirectory {
                    let shouldExpand = expandedFolders.contains(child.url.path)
                    if shouldExpand {
                        child.isExpanded = true
                    }
                }
            }
            node.children = children
            // Recursively load children for expanded subdirectories
            for child in children where child.isDirectory && child.isExpanded {
                await loadChildrenIfNeeded(for: child)
            }
        } catch {
            print("[RemoteFileTreeProvider] Failed to list \(path): \(error)")
        }
    }

    /// Build FileTreeNode array from DirectoryEntry array (single level, no recursion)
    private func buildNodes(from entries: [DirectoryEntry], parentPath: String, depth: Int) -> [FileTreeNode] {
        let sorted = entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        var nodes: [FileTreeNode] = []
        for entry in sorted {
            if !showHiddenFiles && entry.name.hasPrefix(".") { continue }
            let fullPath = (parentPath as NSString).appendingPathComponent(entry.name)
            let url = URL(fileURLWithPath: fullPath)

            if entry.isDirectory {
                if Self.ignoredDirectories.contains(entry.name) { continue }
                let node = FileTreeNode(
                    name: entry.name,
                    url: url,
                    isDirectory: true,
                    depth: depth
                )
                nodes.append(node)
            } else {
                let ext = (entry.name as NSString).pathExtension.lowercased()
                if Self.markdownExtensions.contains(ext) {
                    let node = FileTreeNode(
                        name: entry.name,
                        url: url,
                        isDirectory: false,
                        depth: depth
                    )
                    nodes.append(node)
                }
            }
        }
        return nodes
    }

    /// Wire up expansion callback
    private func wireUpNode(_ node: FileTreeNode) {
        node.onExpandedChange = { [weak self] path, expanded in
            self?.handleFolderExpansionChange(path: path, expanded: expanded)
            if expanded {
                self?.expandFolder(at: path)
            }
        }
    }

    /// Find and load children for a folder
    private func expandFolder(at path: String) {
        guard let node = findNode(at: path, in: rootNodes) else { return }
        Task {
            await loadChildrenIfNeeded(for: node)
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

    // MARK: - Merge

    /// Merge a single level, preserving existing node identity and loaded children
    private func mergeLevel(
        existing: [FileTreeNode],
        incoming: [FileTreeNode],
        parentPath: String,
        depth: Int
    ) -> [FileTreeNode] {
        var existingByURL: [URL: FileTreeNode] = [:]
        for node in existing {
            existingByURL[node.url] = node
        }

        return incoming.map { newNode in
            if let existingNode = existingByURL[newNode.url] {
                if existingNode.isDirectory && existingNode.childrenLoaded {
                    // Re-enumerate this loaded directory
                    Task {
                        let path = existingNode.url.path
                        let childDepth = depth + 1
                        guard let entries = try? await self.fileProvider.listDirectory(at: path) else { return }
                        let newChildren = self.buildNodes(from: entries, parentPath: path, depth: childDepth)
                        existingNode.children = self.mergeLevel(
                            existing: existingNode.children,
                            incoming: newChildren,
                            parentPath: path,
                            depth: childDepth
                        )
                    }
                }
                return existingNode
            } else {
                wireUpNode(newNode)
                let shouldExpand = expandedFolders.contains(newNode.url.path)
                if shouldExpand && newNode.isDirectory {
                    let callback = newNode.onExpandedChange
                    newNode.onExpandedChange = nil
                    newNode.isExpanded = true
                    newNode.onExpandedChange = callback
                    Task {
                        await self.loadChildrenIfNeeded(for: newNode)
                    }
                }
                return newNode
            }
        }
    }

    private func handleFolderExpansionChange(path: String, expanded: Bool) {
        if expanded {
            expandedFolders.insert(path)
        } else {
            expandedFolders.remove(path)
        }

        if let rootPath = rootDirectory {
            onExpandedFoldersChange?(rootPath, expandedFolders)
        }
    }

    /// Apply expanded folders state to existing nodes
    public func applyExpandedFolders(_ folders: Set<String>) {
        expandedFolders = folders
        Task {
            await applyExpandedStateToNodes(rootNodes)
        }
    }

    private func applyExpandedStateToNodes(_ nodes: [FileTreeNode]) async {
        for node in nodes where node.isDirectory {
            let callback = node.onExpandedChange
            node.onExpandedChange = nil
            let shouldExpand = expandedFolders.contains(node.url.path) || node.depth == 0
            node.isExpanded = shouldExpand
            node.onExpandedChange = callback

            if shouldExpand {
                await loadChildrenIfNeeded(for: node)
            }
            await applyExpandedStateToNodes(node.children)
        }
    }
}

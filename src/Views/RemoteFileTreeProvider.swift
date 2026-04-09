import Foundation
import RedmarginCore

protocol RemoteFileTreeProviding {
    func detectGitRepo(for path: String) async throws -> String?
    func listDirectory(at path: String) async throws -> [DirectoryEntry]
    func watchDirectory(at path: String, onChange: @escaping ([String]) -> Void) async -> WatchToken
    func unwatchDirectory(_ token: WatchToken) async
}

extension RemoteFileProvider: RemoteFileTreeProviding {}

/// Provides a hierarchical tree of files from a remote directory for sidebar display.
/// Uses lazy single-level loading — only enumerates one directory at a time via listDirectory RPC.
@MainActor
public class RemoteFileTreeProvider: ObservableObject {
    @Published public private(set) var rootNodes: [FileTreeNode] = []
    @Published public private(set) var rootDirectory: String?
    @Published public private(set) var isLoading = false

    private let currentFilePath: String
    private let fileProvider: any RemoteFileTreeProviding
    private let pathIsDirectory: Bool
    private var expandedFolders: Set<String> = []
    private var expandedFoldersRootPath: String?
    /// One watch per visible directory (root + expanded folders).
    /// Nested watches are required because each server-side watch is
    /// single-level and only reports changes to its own direntries.
    private var directoryWatchTokens: [String: WatchToken] = [:]
    private var stateObserverTask: Task<Void, Never>?
    private var restoreExpandedFoldersTask: Task<Void, Never>?
    private var loadGeneration = 0

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

    init(
        currentFilePath: String,
        fileProvider: any RemoteFileTreeProviding,
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
        loadGeneration += 1
        let generation = loadGeneration
        restoreExpandedFoldersTask?.cancel()
        restoreExpandedFoldersTask = nil
        isLoading = true

        // Try to find Git repo root first
        do {
            if let repoRoot = try await fileProvider.detectGitRepo(for: currentFilePath) {
                guard isCurrentLoad(generation) else { return }
                rootDirectory = repoRoot
                await loadRootLevel(from: repoRoot, loadGeneration: generation)
                guard isCurrentLoad(generation) else { return }
                await setupDirectoryWatching(for: repoRoot)
                guard isCurrentLoad(generation) else { return }
                isLoading = false
                restoreExpandedFoldersAfterLoad(rootPath: repoRoot, loadGeneration: generation)
                return
            }
        } catch {
            print("[RemoteFileTreeProvider] Git detection failed: \(error)")
        }

        // Fall back to the directory itself (if opened as folder) or file's parent
        let fallbackDir = pathIsDirectory
            ? currentFilePath
            : (currentFilePath as NSString).deletingLastPathComponent
        guard isCurrentLoad(generation) else { return }
        rootDirectory = fallbackDir
        await loadRootLevel(from: fallbackDir, loadGeneration: generation)
        guard isCurrentLoad(generation) else { return }
        await setupDirectoryWatching(for: fallbackDir)
        guard isCurrentLoad(generation) else { return }
        isLoading = false
        restoreExpandedFoldersAfterLoad(rootPath: fallbackDir, loadGeneration: generation)
    }

    private func isCurrentLoad(_ generation: Int, rootPath: String? = nil) -> Bool {
        guard loadGeneration == generation else { return false }
        if let rootPath {
            return rootDirectory == rootPath
        }
        return true
    }

    private func restoredExpandedFolders(for rootPath: String) -> Set<String> {
        if expandedFoldersRootPath == rootPath {
            return expandedFolders
        }
        return expandedFoldersLoader?(rootPath) ?? []
    }

    private func restoreExpandedFoldersAfterLoad(rootPath: String, loadGeneration: Int) {
        let foldersToRestore = restoredExpandedFolders(for: rootPath)
        expandedFoldersRootPath = rootPath
        expandedFolders = foldersToRestore

        guard !foldersToRestore.isEmpty else { return }

        restoreExpandedFoldersTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.applyExpandedFolders(foldersToRestore, rootPath: rootPath, loadGeneration: loadGeneration)
        }
    }

    private func setExpandedState(_ expanded: Bool, for node: FileTreeNode) {
        let callback = node.onExpandedChange
        node.onExpandedChange = nil
        node.isExpanded = expanded
        node.onExpandedChange = callback
    }

    private func setupDirectoryWatching(for rootPath: String) async {
        await unwatchAllDirectories()
        await watchDirectoryIfNeeded(rootPath)
    }

    private func watchDirectoryIfNeeded(_ path: String) async {
        guard directoryWatchTokens[path] == nil else { return }
        let token = await fileProvider.watchDirectory(at: path) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        directoryWatchTokens[path] = token
    }

    private func unwatchDirectory(_ path: String) async {
        guard let token = directoryWatchTokens.removeValue(forKey: path) else { return }
        await fileProvider.unwatchDirectory(token)
    }

    private func unwatchAllDirectories() async {
        let tokens = directoryWatchTokens.values
        directoryWatchTokens.removeAll()
        for token in tokens {
            await fileProvider.unwatchDirectory(token)
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
    private func loadRootLevel(from directory: String, loadGeneration: Int) async {
        do {
            let entries = try await fileProvider.listDirectory(at: directory)
            guard isCurrentLoad(loadGeneration, rootPath: directory) else { return }
            let nodes = buildNodes(from: entries, parentPath: directory, depth: 0)
            for node in nodes {
                wireUpNode(node)
            }
            rootNodes = nodes
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
                        setExpandedState(true, for: child)
                    }
                }
            }
            node.children = children
            // Expanded folder is now visible — watch it so sidebar reflects
            // any changes inside it without polling the entire tree.
            await watchDirectoryIfNeeded(path)
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
                    depth: depth,
                    isExpanded: false
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
                    setExpandedState(true, for: newNode)
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
            // Collapsing hides the folder and everything under it — drop the
            // watches so the server isn't tracking directories the user
            // can't see.
            Task { [weak self] in
                await self?.unwatchDirectoryAndDescendants(path)
            }
        }

        if let rootPath = rootDirectory {
            onExpandedFoldersChange?(rootPath, expandedFolders)
        }
    }

    private func unwatchDirectoryAndDescendants(_ path: String) async {
        let prefix = path.hasSuffix("/") ? path : path + "/"
        let victims = directoryWatchTokens.keys.filter { $0 == path || $0.hasPrefix(prefix) }
        for victim in victims {
            await unwatchDirectory(victim)
        }
    }

    /// Apply expanded folders state to existing nodes
    public func applyExpandedFolders(_ folders: Set<String>) {
        guard let rootPath = rootDirectory else { return }
        restoreExpandedFoldersTask?.cancel()
        restoreExpandedFoldersTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.applyExpandedFolders(folders, rootPath: rootPath, loadGeneration: self.loadGeneration)
        }
    }

    private func applyExpandedFolders(_ folders: Set<String>, rootPath: String, loadGeneration: Int) async {
        guard isCurrentLoad(loadGeneration, rootPath: rootPath) else { return }
        expandedFoldersRootPath = rootPath
        expandedFolders = folders
        await applyExpandedStateToNodes(rootNodes, rootPath: rootPath, loadGeneration: loadGeneration)
    }

    private func applyExpandedStateToNodes(_ nodes: [FileTreeNode], rootPath: String, loadGeneration: Int) async {
        for node in nodes where node.isDirectory {
            guard !Task.isCancelled else { return }
            guard isCurrentLoad(loadGeneration, rootPath: rootPath) else { return }
            let shouldExpand = expandedFolders.contains(node.url.path)
            setExpandedState(shouldExpand, for: node)

            if shouldExpand {
                await loadChildrenIfNeeded(for: node)
            }
            guard isCurrentLoad(loadGeneration, rootPath: rootPath) else { return }
            await applyExpandedStateToNodes(node.children, rootPath: rootPath, loadGeneration: loadGeneration)
        }
    }
}

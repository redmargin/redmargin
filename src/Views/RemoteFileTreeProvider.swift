import Foundation
import RedmarginCore

protocol RemoteFileTreeProviding {
    func detectGitRepo(for path: String) async throws -> String?
    func gitStatus(for path: String) async throws -> GitStatusSnapshot
    func listDirectory(at path: String) async throws -> [DirectoryEntry]
    func watchDirectory(at path: String, onChange: @escaping ([String]) -> Void) async -> WatchToken
    func unwatchDirectory(_ token: WatchToken) async
    func watchGitRepo(at repoRoot: String, onChange: @escaping () -> Void) async -> WatchToken
    func unwatch(_ token: WatchToken) async
}

extension RemoteFileProvider: RemoteFileTreeProviding {}

/// Provides a hierarchical tree of files from a remote directory for sidebar display.
/// Uses lazy single-level loading — only enumerates one directory at a time via listDirectory RPC.
@MainActor
public class RemoteFileTreeProvider: ObservableObject {
    @Published public private(set) var rootNodes: [FileTreeNode] = []
    @Published public private(set) var rootDirectory: String?
    @Published public private(set) var isLoading = false
    @Published public private(set) var loadError: String?

    private let currentFilePath: String
    private let fileProvider: any RemoteFileTreeProviding
    private let pathIsDirectory: Bool
    private var expandedFolders: Set<String> = []
    private var expandedFoldersRootPath: String?
    /// One watch per visible directory (root + expanded folders).
    /// Nested watches are required because each server-side watch is
    /// single-level and only reports changes to its own direntries.
    private var directoryWatchTokens: [String: WatchToken] = [:]
    private var gitWatchToken: WatchToken?
    private var reconnectHost: String?
    private var reconnectObserver: NSObjectProtocol?
    private var connectObserver: NSObjectProtocol?
    private var restoreExpandedFoldersTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var gitStatusTask: Task<Void, Never>?
    private var refreshGeneration = 0
    private var loadGeneration = 0
    private var gitStatuses: [String: GitFileStatus] = [:]

    /// Timeout for sidebar refresh operations. Tests inject a shorter value.
    var refreshTimeout: TimeInterval = 15

    /// Callback when expanded folders change (path of root, set of expanded folder paths)
    public var onExpandedFoldersChange: ((String, Set<String>) -> Void)?

    /// Called once rootDirectory is determined to load persisted expanded folders
    private let expandedFoldersLoader: ((String) -> Set<String>)?

    public var showHiddenFiles: Bool = false {
        didSet {
            if oldValue != showHiddenFiles { refresh() }
        }
    }

    public var showGitStatus: Bool = true {
        didSet {
            guard oldValue != showGitStatus else { return }
            if showGitStatus {
                refreshGitStatus()
            } else {
                clearGitStatus(in: rootNodes)
                Task { [weak self] in
                    await self?.unwatchGitStatus()
                }
            }
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
        reconnectHost: String? = nil,
        expandedFolders: Set<String> = [],
        isDirectory: Bool = false,
        connectsOnDemand: Bool = false,
        expandedFoldersLoader: ((String) -> Set<String>)? = nil
    ) {
        self.currentFilePath = currentFilePath
        self.fileProvider = fileProvider
        self.pathIsDirectory = isDirectory
        self.expandedFolders = expandedFolders
        self.expandedFoldersLoader = expandedFoldersLoader
        self.reconnectHost = reconnectHost
        if connectsOnDemand {
            observeConnectNotification()
        } else {
            Task {
                await loadFiles()
            }
        }
        if reconnectHost != nil {
            observeReconnectNotification()
        }
    }

    init(
        currentFilePath: String,
        fileProvider: any RemoteFileTreeProviding,
        reconnectHost: String? = nil,
        expandedFolders: Set<String> = [],
        isDirectory: Bool = false,
        connectsOnDemand: Bool = false,
        expandedFoldersLoader: ((String) -> Set<String>)? = nil
    ) {
        self.currentFilePath = currentFilePath
        self.fileProvider = fileProvider
        self.pathIsDirectory = isDirectory
        self.expandedFolders = expandedFolders
        self.expandedFoldersLoader = expandedFoldersLoader
        self.reconnectHost = reconnectHost
        if connectsOnDemand {
            observeConnectNotification()
        } else {
            Task {
                await loadFiles()
            }
        }
        if reconnectHost != nil {
            observeReconnectNotification()
        }
    }

    /// Observes the first connect of an on-demand window so a deferred tree loads
    /// once the connection is live. Filtered to this window's location.
    private func observeConnectNotification() {
        guard let host = reconnectHost else { return }
        let expectedKey = "\(host):\(currentFilePath)"
        connectObserver = NotificationCenter.default.addObserver(
            forName: .remoteWindowDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  (notification.object as? String) == expectedKey else { return }
            Task { @MainActor in
                await self.loadFiles()
            }
        }
    }

    private func observeReconnectNotification() {
        let expectedHost = reconnectHost
        reconnectObserver = NotificationCenter.default.addObserver(
            forName: .sshConnectionReconnected,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let host = notification.object as? String,
                  host == expectedHost else { return }
            Task { @MainActor in
                await self.loadFiles()
            }
        }
    }

    deinit {
        if let observer = reconnectObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = connectObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        refreshTask?.cancel()
        gitStatusTask?.cancel()
        restoreExpandedFoldersTask?.cancel()
    }

    /// Loads the root directory
    public func loadFiles() async {
        refreshTask?.cancel()
        refreshTask = nil
        gitStatusTask?.cancel()
        await unwatchGitStatus()
        clearGitStatus(in: rootNodes)
        loadGeneration += 1
        let generation = loadGeneration
        restoreExpandedFoldersTask?.cancel()
        restoreExpandedFoldersTask = nil
        isLoading = true
        loadError = nil

        if !pathIsDirectory {
            // File opens use the surrounding Git repo as the sidebar root when available.
            // Directory opens must honor the explicitly opened folder, including ignored subtrees.
            do {
                if let repoRoot = try await detectGitRepoInteractively(
                    for: currentFilePath,
                    pingFirst: true
                ) {
                    guard isCurrentLoad(generation) else { return }
                    rootDirectory = repoRoot
                    let loaded = await loadRootLevel(from: repoRoot, loadGeneration: generation)
                    guard isCurrentLoad(generation) else { return }
                    if loaded {
                        await setupDirectoryWatching(for: repoRoot)
                    }
                    guard isCurrentLoad(generation) else { return }
                    isLoading = false
                    if loaded {
                        restoreExpandedFoldersAfterLoad(rootPath: repoRoot, loadGeneration: generation)
                    }
                    return
                }
            } catch {
                print("[RemoteFileTreeProvider] Git detection failed: \(error)")
            }
        }

        // Fall back to the directory itself (if opened as folder) or file's parent
        let fallbackDir = pathIsDirectory
            ? currentFilePath
            : (currentFilePath as NSString).deletingLastPathComponent
        guard isCurrentLoad(generation) else { return }
        rootDirectory = fallbackDir
        let loaded = await loadRootLevel(from: fallbackDir, loadGeneration: generation)
        guard isCurrentLoad(generation) else { return }
        if loaded {
            await setupDirectoryWatching(for: fallbackDir)
        }
        guard isCurrentLoad(generation) else { return }
        isLoading = false
        if loaded {
            restoreExpandedFoldersAfterLoad(rootPath: fallbackDir, loadGeneration: generation)
        }
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

    /// Refreshes visible levels — root + any expanded directories.
    /// Cancels any previous refresh, tracks by generation, and times out
    /// preserving the existing tree.
    public func refresh() {
        guard let root = rootDirectory else { return }
        print("[RemoteFileTreeProvider] refresh() for \(root)")

        refreshTask?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration
        let capturedRoot = root
        let timeout = refreshTimeout
        isLoading = true

        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let result: [FileTreeNode]? = await withTaskGroup(of: [FileTreeNode]?.self) { group in
                group.addTask { @MainActor in
                    await self.performRefresh(root: capturedRoot, generation: generation)
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    return nil
                }
                let first = await group.next() ?? nil
                group.cancelAll()
                return first
            }

            guard !Task.isCancelled,
                  self.refreshGeneration == generation,
                  self.rootDirectory == capturedRoot else {
                return
            }

            if let nodes = result {
                self.rootNodes = nodes
                self.loadError = nil
                self.refreshGitStatus()
            } else {
                print("[RemoteFileTreeProvider] refresh timed out, preserving existing tree")
                self.loadError = "Could not refresh the remote file list."
            }
            self.isLoading = false
        }
    }

    /// Performs the actual refresh work: re-lists root and visible expanded folders.
    /// Returns the merged node array, or nil on failure.
    private func performRefresh(root: String, generation: Int) async -> [FileTreeNode]? {
        guard let entries = try? await listDirectoryInteractively(at: root, pingFirst: false) else { return nil }
        guard !Task.isCancelled, refreshGeneration == generation else { return nil }

        let newNodes = buildNodes(from: entries, parentPath: root, depth: 0)
        let merged = await mergeLevel(
            existing: rootNodes,
            incoming: newNodes,
            parentPath: root,
            depth: 0,
            refreshGeneration: generation
        )
        return merged
    }

    // MARK: - Lazy Loading

    /// Load root level via a single listDirectory call
    private func loadRootLevel(from directory: String, loadGeneration: Int) async -> Bool {
        do {
            let entries = try await listDirectoryInteractively(at: directory, pingFirst: true)
            guard isCurrentLoad(loadGeneration, rootPath: directory) else { return false }
            let nodes = buildNodes(from: entries, parentPath: directory, depth: 0)
            for node in nodes {
                wireUpNode(node)
            }
            rootNodes = nodes
            loadError = nil
            refreshGitStatus()
            return true
        } catch {
            print("[RemoteFileTreeProvider] Failed to list root \(directory): \(error)")
            guard isCurrentLoad(loadGeneration, rootPath: directory) else { return false }
            loadError = "Could not load the remote file list."
            return false
        }
    }

    /// Load children for a folder node (single level)
    private func loadChildrenIfNeeded(for node: FileTreeNode) async {
        guard node.isDirectory, !node.childrenLoaded else { return }
        node.childrenLoaded = true

        let path = node.url.path
        let parentDepth = node.depth

        do {
            let entries = try await listDirectoryInteractively(at: path, pingFirst: true)
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
            applyGitStatus(to: children)
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

    /// Merge a single level, preserving existing node identity and loaded children.
    /// Awaits child directory re-enumeration within the current task so refresh
    /// work is tracked and cancellable.
    private func mergeLevel(
        existing: [FileTreeNode],
        incoming: [FileTreeNode],
        parentPath: String,
        depth: Int,
        refreshGeneration: Int
    ) async -> [FileTreeNode] {
        var existingByURL: [URL: FileTreeNode] = [:]
        for node in existing {
            existingByURL[node.url] = node
        }

        var result: [FileTreeNode] = []
        for newNode in incoming {
            guard !Task.isCancelled, self.refreshGeneration == refreshGeneration else {
                return existing
            }

            if let existingNode = existingByURL[newNode.url] {
                if existingNode.isDirectory && existingNode.childrenLoaded {
                    let path = existingNode.url.path
                    let childDepth = depth + 1
                    if let entries = try? await listDirectoryInteractively(at: path, pingFirst: false) {
                        guard !Task.isCancelled, self.refreshGeneration == refreshGeneration else {
                            return existing
                        }
                        let newChildren = buildNodes(from: entries, parentPath: path, depth: childDepth)
                        let mergedChildren = await mergeLevel(
                            existing: existingNode.children,
                            incoming: newChildren,
                            parentPath: path,
                            depth: childDepth,
                            refreshGeneration: refreshGeneration
                        )
                        existingNode.children = mergedChildren
                    }
                }
                result.append(existingNode)
            } else {
                wireUpNode(newNode)
                let shouldExpand = expandedFolders.contains(newNode.url.path)
                if shouldExpand && newNode.isDirectory {
                    setExpandedState(true, for: newNode)
                    await loadChildrenIfNeeded(for: newNode)
                }
                result.append(newNode)
            }
        }
        return result
    }

    private func refreshGitStatus() {
        guard showGitStatus, let root = rootDirectory else { return }
        gitStatusTask?.cancel()
        gitStatusTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await self.fileProvider.gitStatus(for: root)
                guard !Task.isCancelled else { return }
                self.gitStatuses = snapshot.statuses
                self.applyGitStatus(to: self.rootNodes)
                await self.setupGitWatching(repoRoot: snapshot.repoRoot)
            } catch {
                guard !Task.isCancelled else { return }
                self.gitStatuses = [:]
                self.applyGitStatus(to: self.rootNodes)
            }
        }
    }

    private func setupGitWatching(repoRoot: String?) async {
        await unwatchGitStatus()

        guard let repoRoot, !repoRoot.isEmpty else { return }
        gitWatchToken = await fileProvider.watchGitRepo(at: repoRoot) { [weak self] in
            Task { @MainActor in
                self?.refreshGitStatus()
            }
        }
    }

    private func unwatchGitStatus() async {
        if let token = gitWatchToken {
            gitWatchToken = nil
            await fileProvider.unwatch(token)
        }
    }

    private func applyGitStatus(to nodes: [FileTreeNode]) {
        guard showGitStatus else { return }
        for node in nodes {
            node.gitStatus = node.isDirectory ? nil : gitStatuses[node.url.standardizedFileURL.path]
            if node.isDirectory {
                applyGitStatus(to: node.children)
            }
        }
    }

    private func clearGitStatus(in nodes: [FileTreeNode]) {
        gitStatusTask?.cancel()
        gitStatuses = [:]
        for node in nodes {
            node.gitStatus = nil
            clearGitStatus(in: node.children)
        }
    }

    private func detectGitRepoInteractively(for path: String, pingFirst: Bool) async throws -> String? {
        if let remoteFileProvider = fileProvider as? RemoteFileProvider {
            return try await detectRemoteGitRepo(
                fileProvider: remoteFileProvider,
                path: path,
                pingFirst: pingFirst
            )
        }
        return try await fileProvider.detectGitRepo(for: path)
    }

    private func listDirectoryInteractively(at path: String, pingFirst: Bool) async throws -> [DirectoryEntry] {
        if let remoteFileProvider = fileProvider as? RemoteFileProvider {
            return try await listRemoteDirectoryEntries(
                fileProvider: remoteFileProvider,
                path: path,
                pingFirst: pingFirst
            )
        }
        return try await fileProvider.listDirectory(at: path)
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

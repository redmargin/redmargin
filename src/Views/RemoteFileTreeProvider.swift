import Foundation
import RedmarginCore

/// Provides a hierarchical tree of Markdown files from a remote directory for sidebar display.
/// Uses the Git repo root if available, otherwise falls back to the file's parent directory.
@MainActor
public class RemoteFileTreeProvider: ObservableObject {
    @Published public private(set) var rootNodes: [FileTreeNode] = []
    @Published public private(set) var rootDirectory: String?
    @Published public private(set) var isLoading = false

    private let currentFilePath: String
    private let fileProvider: RemoteFileProvider
    private var expandedFolders: Set<String> = []
    private var directoryWatchToken: WatchToken?
    private var stateObserverTask: Task<Void, Never>?

    /// Callback when expanded folders change (path of root, set of expanded folder paths)
    public var onExpandedFoldersChange: ((String, Set<String>) -> Void)?

    public init(
        currentFilePath: String,
        fileProvider: RemoteFileProvider,
        stateChanges: AsyncStream<SSHConnectionState>? = nil,
        expandedFolders: Set<String> = []
    ) {
        self.currentFilePath = currentFilePath
        self.fileProvider = fileProvider
        self.expandedFolders = expandedFolders
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

    /// Loads markdown files from the appropriate root directory
    public func loadFiles() async {
        isLoading = true
        defer { isLoading = false }

        // Try to find Git repo root first
        do {
            if let repoRoot = try await fileProvider.detectGitRepo(for: currentFilePath) {
                rootDirectory = repoRoot
                rootNodes = await buildTree(from: repoRoot)
                await setupDirectoryWatching(for: repoRoot)
                return
            }
        } catch {
            print("[RemoteFileTreeProvider] Git detection failed: \(error)")
        }

        // Fall back to file's parent directory
        let parentDir = (currentFilePath as NSString).deletingLastPathComponent
        rootDirectory = parentDir
        rootNodes = await buildTree(from: parentDir)
        await setupDirectoryWatching(for: parentDir)
    }

    private func setupDirectoryWatching(for path: String) async {
        // Clean up any existing watch
        if let token = directoryWatchToken {
            await fileProvider.unwatchDirectory(token)
        }

        directoryWatchToken = await fileProvider.watchDirectory(at: path) { [weak self] files in
            Task { @MainActor in
                self?.handleDirectoryChanged(files: files)
            }
        }
    }

    private func handleDirectoryChanged(files: [String]) {
        guard let root = rootDirectory else { return }
        print("[RemoteFileTreeProvider] Directory changed, rebuilding tree (\(files.count) files)")
        rootNodes = buildTreeFromPaths(files, rootPath: root)
    }

    /// Refreshes the file list
    public func refresh() {
        Task {
            guard let root = rootDirectory else { return }
            isLoading = true
            rootNodes = await buildTree(from: root)
            isLoading = false
        }
    }

    /// Directories to skip when enumerating files (used by legacy recursive fallback)
    private static let ignoredDirectories: Set<String> = [
        ".git", "node_modules", ".build", "build", "DerivedData",
        ".cache", ".npm", "vendor", "Pods", ".svn", ".hg"
    ]

    /// File extensions to include (used by legacy recursive fallback)
    private static let markdownExtensions: Set<String> = ["md", "markdown"]

    private func buildTree(from directory: String) async -> [FileTreeNode] {
        // Try single-call approach (requires server with FindMarkdownFiles support)
        do {
            let paths = try await fileProvider.findMarkdownFiles(in: directory)
            return buildTreeFromPaths(paths, rootPath: directory)
        } catch {
            // Fall back to recursive listing for older servers
            print("[RemoteFileTreeProvider] FindMarkdownFiles not available, falling back to recursive listing")
            return await buildTreeRecursive(at: directory, depth: 0)
        }
    }

    private func buildTreeRecursive(at directory: String, depth: Int) async -> [FileTreeNode] {
        var nodes: [FileTreeNode] = []

        let entries: [DirectoryEntry]
        do {
            entries = try await fileProvider.listDirectory(at: directory)
        } catch {
            print("[RemoteFileTreeProvider] Failed to list \(directory): \(error)")
            return []
        }

        let sorted = entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        for entry in sorted {
            let fullPath = (directory as NSString).appendingPathComponent(entry.name)
            let url = URL(fileURLWithPath: fullPath)

            if entry.isDirectory {
                if Self.ignoredDirectories.contains(entry.name) { continue }

                let children = await buildTreeRecursive(at: fullPath, depth: depth + 1)
                if !children.isEmpty {
                    let shouldExpand = expandedFolders.contains(fullPath) || depth == 0
                    let node = FileTreeNode(
                        name: entry.name,
                        url: url,
                        isDirectory: true,
                        depth: depth,
                        children: children,
                        isExpanded: shouldExpand
                    )
                    node.onExpandedChange = { [weak self] path, expanded in
                        self?.handleFolderExpansionChange(path: path, expanded: expanded)
                    }
                    nodes.append(node)
                }
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

    /// Builds a hierarchical tree from a flat list of relative file paths.
    /// Uses a trie to group files into their directory structure.
    private func buildTreeFromPaths(_ relativePaths: [String], rootPath: String) -> [FileTreeNode] {
        // Build intermediate trie from flat paths
        let root = PathTrie()
        for path in relativePaths {
            let components = path.split(separator: "/").map(String.init)
            var current = root
            for (index, component) in components.enumerated() {
                if index == components.count - 1 {
                    current.files.append(component)
                } else {
                    if current.subdirs[component] == nil {
                        current.subdirs[component] = PathTrie()
                    }
                    current = current.subdirs[component]!
                }
            }
        }

        return convertTrieToNodes(root, parentPath: rootPath, depth: 0)
    }

    private func convertTrieToNodes(_ trie: PathTrie, parentPath: String, depth: Int) -> [FileTreeNode] {
        var nodes: [FileTreeNode] = []

        // Directories first, sorted
        let sortedDirNames = trie.subdirs.keys.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }

        for dirName in sortedDirNames {
            let dirContent = trie.subdirs[dirName]!
            let fullPath = (parentPath as NSString).appendingPathComponent(dirName)
            let url = URL(fileURLWithPath: fullPath)
            let children = convertTrieToNodes(dirContent, parentPath: fullPath, depth: depth + 1)

            let shouldExpand = expandedFolders.contains(fullPath) || depth == 0
            let node = FileTreeNode(
                name: dirName,
                url: url,
                isDirectory: true,
                depth: depth,
                children: children,
                isExpanded: shouldExpand
            )
            node.onExpandedChange = { [weak self] path, expanded in
                self?.handleFolderExpansionChange(path: path, expanded: expanded)
            }
            nodes.append(node)
        }

        // Files, sorted
        let sortedFiles = trie.files.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }

        for fileName in sortedFiles {
            let fullPath = (parentPath as NSString).appendingPathComponent(fileName)
            let url = URL(fileURLWithPath: fullPath)
            let node = FileTreeNode(name: fileName, url: url, isDirectory: false, depth: depth)
            nodes.append(node)
        }

        return nodes
    }

    private func handleFolderExpansionChange(path: String, expanded: Bool) {
        if expanded {
            expandedFolders.insert(path)
        } else {
            expandedFolders.remove(path)
        }

        // Notify via callback
        if let rootPath = rootDirectory {
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
            node.isExpanded = expandedFolders.contains(node.url.path) || node.depth == 0
            node.onExpandedChange = callback

            // Recursively apply to children
            applyExpandedStateToNodes(node.children)
        }
    }
}

/// Intermediate trie node for building file tree from flat paths
private class PathTrie {
    var subdirs: [String: PathTrie] = [:]
    var files: [String] = []
}

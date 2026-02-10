import Foundation
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
    private var directoryWatcher: DirectoryWatcher?
    private var expandedFolders: Set<String> = []
    private let autoExpandRoot: Bool

    /// Callback when expanded folders change (path of root, set of expanded folder paths)
    public var onExpandedFoldersChange: ((String, Set<String>) -> Void)?

    /// Directories to skip when enumerating files
    private static let ignoredDirectories: Set<String> = [
        ".git", "node_modules", ".build", "build", "DerivedData",
        ".cache", ".npm", "vendor", "Pods", ".svn", ".hg"
    ]

    /// File extensions to include
    private static let markdownExtensions: Set<String> = ["md", "markdown"]

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
        self.rootNodes = buildTree(from: rootDirectory)
        setupDirectoryWatcher(for: rootDirectory)
    }

    /// Loads markdown files from the appropriate root directory
    public func loadFiles() async {
        guard let currentFileURL else { return }

        isLoading = true
        defer { isLoading = false }

        // Try to find Git repo root first
        do {
            if let repoRoot = try await GitRepoDetector.detectRepoRoot(forFile: currentFileURL) {
                rootDirectory = repoRoot
                rootNodes = buildTree(from: repoRoot)
                setupDirectoryWatcher(for: repoRoot)
                return
            }
        } catch {
            print("[FileTreeProvider] Git detection failed: \(error)")
        }

        // Fall back to file's parent directory
        let parentDir = currentFileURL.deletingLastPathComponent()
        rootDirectory = parentDir
        rootNodes = buildTree(from: parentDir)
        setupDirectoryWatcher(for: parentDir)
    }

    /// Refreshes the file list
    public func refresh() {
        guard let root = rootDirectory else { return }
        rootNodes = buildTree(from: root)
    }

    private func buildTree(from directory: URL) -> [FileTreeNode] {
        return buildTreeRecursive(at: directory, depth: 0)
    }

    private func buildTreeRecursive(at directory: URL, depth: Int) -> [FileTreeNode] {
        var nodes: [FileTreeNode] = []

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        // Sort: directories first, then alphabetically
        let sorted = contents.sorted { lhs, rhs in
            let lhsIsDir = (try? lhs.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let rhsIsDir = (try? rhs.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

            if lhsIsDir != rhsIsDir {
                return lhsIsDir  // Directories first
            }
            return lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent) == .orderedAscending
        }

        for url in sorted {
            let name = url.lastPathComponent
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

            if isDir {
                // Skip ignored directories
                if Self.ignoredDirectories.contains(name) {
                    continue
                }

                // Recursively get children
                let children = buildTreeRecursive(at: url, depth: depth + 1)

                // Only include directory if it has markdown files (directly or nested)
                if !children.isEmpty {
                    // Check if this folder should be expanded
                    let shouldExpand = expandedFolders.contains(url.path) || (autoExpandRoot && depth == 0)
                    let node = FileTreeNode(
                        name: name,
                        url: url,
                        isDirectory: true,
                        depth: depth,
                        children: children,
                        isExpanded: shouldExpand
                    )
                    // Set up callback for expansion changes
                    node.onExpandedChange = { [weak self] path, expanded in
                        self?.handleFolderExpansionChange(path: path, expanded: expanded)
                    }
                    nodes.append(node)
                }
            } else {
                // Check if it's a markdown file
                let ext = url.pathExtension.lowercased()
                if Self.markdownExtensions.contains(ext) {
                    let node = FileTreeNode(
                        name: name,
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

    private func setupDirectoryWatcher(for directory: URL) {
        directoryWatcher = DirectoryWatcher(url: directory) { [weak self] in
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

/// Watches a directory for changes (file additions/removals)
class DirectoryWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let url: URL
    private let onChange: () -> Void

    init?(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange

        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            print("[DirectoryWatcher] Failed to open: \(url.path)")
            return nil
        }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename],
            queue: .main
        )

        source?.setEventHandler { [weak self] in
            self?.onChange()
        }

        source?.setCancelHandler { }
        source?.resume()
    }

    deinit {
        source?.cancel()
        if fileDescriptor >= 0 {
            close(fileDescriptor)
        }
    }
}

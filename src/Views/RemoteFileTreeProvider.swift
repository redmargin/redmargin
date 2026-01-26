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

    /// Callback when expanded folders change (path of root, set of expanded folder paths)
    public var onExpandedFoldersChange: ((String, Set<String>) -> Void)?

    /// Directories to skip when enumerating files
    private static let ignoredDirectories: Set<String> = [
        ".git", "node_modules", ".build", "build", "DerivedData",
        ".cache", ".npm", "vendor", "Pods", ".svn", ".hg"
    ]

    /// File extensions to include
    private static let markdownExtensions: Set<String> = ["md", "markdown"]

    public init(currentFilePath: String, fileProvider: RemoteFileProvider, expandedFolders: Set<String> = []) {
        self.currentFilePath = currentFilePath
        self.fileProvider = fileProvider
        self.expandedFolders = expandedFolders
        Task {
            await loadFiles()
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
                return
            }
        } catch {
            print("[RemoteFileTreeProvider] Git detection failed: \(error)")
        }

        // Fall back to file's parent directory
        let parentDir = (currentFilePath as NSString).deletingLastPathComponent
        rootDirectory = parentDir
        rootNodes = await buildTree(from: parentDir)
    }

    /// Refreshes the file list
    public func refresh() {
        Task {
            guard let root = rootDirectory else { return }
            rootNodes = await buildTree(from: root)
        }
    }

    private func buildTree(from directory: String) async -> [FileTreeNode] {
        return await buildTreeRecursive(at: directory, depth: 0)
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

        // Sort: directories first, then alphabetically
        let sorted = entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory  // Directories first
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        for entry in sorted {
            let fullPath = (directory as NSString).appendingPathComponent(entry.name)
            let url = URL(fileURLWithPath: fullPath)

            if entry.isDirectory {
                // Skip ignored directories
                if Self.ignoredDirectories.contains(entry.name) {
                    continue
                }

                // Recursively get children
                let children = await buildTreeRecursive(at: fullPath, depth: depth + 1)

                // Only include directory if it has markdown files (directly or nested)
                if !children.isEmpty {
                    // Check if this folder should be expanded
                    let shouldExpand = expandedFolders.contains(fullPath) || depth == 0
                    let node = FileTreeNode(
                        name: entry.name,
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

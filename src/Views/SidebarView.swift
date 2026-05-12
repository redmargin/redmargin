import SwiftUI
import RedmarginCore

/// SwiftUI view displaying a hierarchical tree of Markdown files in the sidebar
public struct SidebarView: View {
    let rootNodes: [FileTreeNode]
    let rootDirectory: String?
    let currentFileURL: URL
    let isLoading: Bool
    let onFileSelected: (URL) -> Void
    let onRefresh: () -> Void

    public init(
        rootNodes: [FileTreeNode],
        rootDirectory: String?,
        currentFileURL: URL,
        isLoading: Bool,
        onFileSelected: @escaping (URL) -> Void,
        onRefresh: @escaping () -> Void
    ) {
        self.rootNodes = rootNodes
        self.rootDirectory = rootDirectory
        self.currentFileURL = currentFileURL
        self.isLoading = isLoading
        self.onFileSelected = onFileSelected
        self.onRefresh = onRefresh
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with root directory name
            if let root = rootDirectory {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text((root as NSString).lastPathComponent)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Refresh file list")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()
            }

            if isLoading {
                Spacer()
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.7)
                    Spacer()
                }
                Spacer()
            } else if rootNodes.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                    Text("No Markdown files")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rootNodes) { node in
                            TreeNodeView(
                                node: node,
                                currentFileURL: currentFileURL,
                                onFileSelected: onFileSelected
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(minWidth: 150)
    }
}

/// A single node in the tree (folder or file)
private struct TreeNodeView: View {
    @ObservedObject var node: FileTreeNode
    let currentFileURL: URL
    let onFileSelected: (URL) -> Void

    private var isSelected: Bool {
        !node.isDirectory && node.url == currentFileURL
    }

    private var indentation: CGFloat {
        CGFloat(node.depth) * 16
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // This node's row
            HStack(spacing: 4) {
                // Disclosure indicator for folders
                if node.isDirectory {
                    Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                } else {
                    Spacer()
                        .frame(width: 12)
                }

                GitStatusIndicator(status: node.isDirectory ? nil : node.gitStatus)

                // Icon
                Image(systemName: node.isDirectory ? "folder.fill" : "doc.text")
                    .font(.system(size: 12))
                    .foregroundColor(node.isDirectory ? .orange : (isSelected ? .accentColor : .secondary))

                // Name
                Text(node.name)
                    .font(.system(size: 12))
                    .fontWeight(isSelected ? .medium : .regular)
                    .lineLimit(1)
                    .foregroundColor(isSelected ? .accentColor : .primary)

                Spacer()
            }
            .padding(.leading, 8 + indentation)
            .padding(.trailing, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture {
                if node.isDirectory {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        node.isExpanded.toggle()
                    }
                } else if !isSelected {
                    onFileSelected(node.url)
                }
            }

            // Children (if expanded)
            if node.isDirectory && node.isExpanded {
                ForEach(node.children) { child in
                    TreeNodeView(
                        node: child,
                        currentFileURL: currentFileURL,
                        onFileSelected: onFileSelected
                    )
                }
            }
        }
    }
}

private struct GitStatusIndicator: View {
    let status: GitFileStatus?

    var body: some View {
        ZStack {
            if let status, status != .clean {
                RoundedRectangle(cornerRadius: 1)
                    .fill(status.sidebarColor)
                    .frame(width: 2, height: 12)
                    .help(status.sidebarDescription)
            }
        }
        .frame(width: 4, height: 12)
    }
}

private extension GitFileStatus {
    var sidebarColor: Color {
        switch self {
        case .clean:
            return .clear
        case .modified:
            return .orange
        case .staged:
            return .green
        case .untracked:
            return .blue
        case .conflict:
            return .red
        }
    }

    var sidebarDescription: String {
        switch self {
        case .clean:
            return "Clean"
        case .modified:
            return "Modified"
        case .staged:
            return "Staged"
        case .untracked:
            return "Untracked"
        case .conflict:
            return "Conflict"
        }
    }
}

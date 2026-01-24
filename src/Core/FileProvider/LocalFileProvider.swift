import Foundation

#if os(macOS)
public class LocalFileProvider: FileProvider {

    // Keep track of active watchers to keep them alive
    private var watchers: [WatchToken: Any] = [:]

    public init() {}

    public func readFile(at path: String) async throws -> String {
        let url = URL(fileURLWithPath: path)
        return try String(contentsOf: url, encoding: .utf8)
    }

    public func writeFile(at path: String, content: String) async throws {
        let url = URL(fileURLWithPath: path)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    public func watchFile(at path: String, onChange: @escaping () -> Void) async -> WatchToken {
        let token = UUID()
        let url = URL(fileURLWithPath: path)

        // FileWatcher is expected to be public and available
        if let watcher = FileWatcher(url: url, onChange: onChange) {
            watchers[token] = watcher
        } else {
            print("[LocalFileProvider] Failed to watch file: \(path)")
        }

        return token
    }

    public func unwatch(_ token: WatchToken) async {
        watchers.removeValue(forKey: token)
    }

    public func detectGitRepo(for path: String) async throws -> String? {
        let url = URL(fileURLWithPath: path)
        let root = try await GitRepoDetector.detectRepoRoot(forFile: url)
        return root?.path
    }

    public func gitDiff(for path: String, repoRoot: String) async throws -> GitChangeResult {
        let fileURL = URL(fileURLWithPath: path)
        let rootURL = URL(fileURLWithPath: repoRoot)
        return try await GitDiffParser.parseChanges(forFile: fileURL, repoRoot: rootURL)
    }

    public func watchGitRepo(at repoRoot: String, onChange: @escaping () -> Void) async -> WatchToken {
        let token = UUID()
        let watcher = GitRepoWatcher(repoRoot: repoRoot, onChange: onChange)
        watchers[token] = watcher
        return token
    }
}

class GitRepoWatcher {
    private let repoRoot: URL
    private let onChange: () -> Void
    private var indexWatcher: FileWatcher?
    private var headWatcher: FileWatcher?
    private var refWatcher: FileWatcher?

    init(repoRoot: String, onChange: @escaping () -> Void) {
        self.repoRoot = URL(fileURLWithPath: repoRoot)
        self.onChange = onChange
        setupWatchers()
    }

    private func setupWatchers() {
        let gitDir = repoRoot.appendingPathComponent(".git")
        let indexURL = gitDir.appendingPathComponent("index")
        let headURL = gitDir.appendingPathComponent("HEAD")

        // Watch index
        indexWatcher = FileWatcher(url: indexURL, writeOnly: true, onChange: onChange)

        // Watch HEAD
        headWatcher = FileWatcher(url: headURL, writeOnly: true) { [weak self] in
            // HEAD changed (branch switch)
            self?.onChange()
            self?.updateRefWatcher()
        }

        updateRefWatcher()
    }

    private func updateRefWatcher() {
        let headURL = repoRoot.appendingPathComponent(".git/HEAD")
        guard let rawContent = try? String(contentsOf: headURL, encoding: .utf8) else {
            return
        }
        let headContent = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !headContent.isEmpty else {
            return
        }

        if headContent.hasPrefix("ref: ") {
            let refPath = String(headContent.dropFirst(5))
            let branchRefURL = repoRoot.appendingPathComponent(".git").appendingPathComponent(refPath)

            // Watch the branch ref file (e.g., refs/heads/main)
            refWatcher = FileWatcher(url: branchRefURL, writeOnly: true, onChange: onChange)
        } else {
            // Detached HEAD, no specific ref to watch
            refWatcher = nil
        }
    }
}
#endif

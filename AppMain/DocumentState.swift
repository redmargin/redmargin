import Foundation
import RedmarginLib

class DocumentState: ObservableObject {
    @Published var content: String
    @Published var gitChanges: GitChangeResult?
    @Published var isRefreshing: Bool = false
    let fileURL: URL
    private var fileWatcher: FileWatcher?
    private var gitIndexWatcher: FileWatcher?
    private var gitHeadWatcher: FileWatcher?
    private var gitBranchRefWatcher: FileWatcher?
    private var repoRoot: URL?
    private var gitChangeTask: Task<Void, Never>?

    init(content: String, fileURL: URL) {
        self.content = content
        self.fileURL = fileURL
        setupFileWatcher()
        detectGitChanges()
    }

    private func setupFileWatcher() {
        fileWatcher = FileWatcher(url: fileURL) { [weak self] in
            self?.reloadContent()
        }
    }

    private func setupGitIndexWatcher() {
        guard let root = repoRoot else { return }
        let indexURL = root.appendingPathComponent(".git/index")
        // writeOnly: true prevents loop where git diff reads index, triggers atime change
        gitIndexWatcher = FileWatcher(url: indexURL, writeOnly: true) { [weak self] in
            self?.detectGitChanges()
        }
    }

    private func setupGitHeadWatcher() {
        guard let root = repoRoot else { return }
        let headURL = root.appendingPathComponent(".git/HEAD")
        gitHeadWatcher = FileWatcher(url: headURL, writeOnly: true) { [weak self] in
            print("[GitWatcher] HEAD changed (branch switch)")
            self?.setupGitBranchRefWatcher() // Re-setup branch watcher for new branch
            self?.detectGitChanges()
        }
    }

    private func setupGitBranchRefWatcher() {
        guard let root = repoRoot else { return }
        let headURL = root.appendingPathComponent(".git/HEAD")

        // Parse HEAD to find current branch
        guard let headContent = try? String(contentsOf: headURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines) else {
            print("[GitWatcher] Could not read HEAD")
            return
        }

        // HEAD contains "ref: refs/heads/branchname" or a commit hash (detached)
        guard headContent.hasPrefix("ref: ") else {
            print("[GitWatcher] Detached HEAD, not watching branch ref")
            gitBranchRefWatcher = nil
            return
        }

        let refPath = String(headContent.dropFirst(5)) // Remove "ref: "
        let branchRefURL = root.appendingPathComponent(".git").appendingPathComponent(refPath)

        print("[GitWatcher] Watching branch ref: \(refPath)")
        gitBranchRefWatcher = FileWatcher(url: branchRefURL, writeOnly: true) { [weak self] in
            print("[GitWatcher] Branch ref changed (commit)")
            self?.detectGitChanges()
        }
    }

    private func reloadContent() {
        print("[DocumentState] reloadContent called for \(fileURL.lastPathComponent)")
        guard let newContent = try? String(contentsOf: fileURL, encoding: .utf8) else {
            print("[DocumentState] Failed to read file")
            return
        }
        guard newContent != content else {
            print("[DocumentState] Content unchanged, skipping update")
            return
        }
        print("[DocumentState] Content changed, updating (\(newContent.count) chars)")
        content = newContent
        detectGitChanges()
    }

    func refresh() {
        isRefreshing = true
        // Force reload even if content unchanged
        if let newContent = try? String(contentsOf: fileURL, encoding: .utf8) {
            content = newContent
        }
        detectGitChanges()
        // Hide spinner after a brief moment
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isRefreshing = false
        }
    }

    private func detectGitChanges() {
        print("[Gutter] detectGitChanges called for \(fileURL.lastPathComponent)")

        // Cancel any in-flight task to avoid race conditions
        gitChangeTask?.cancel()

        gitChangeTask = Task { @MainActor in
            do {
                // Check for cancellation early
                guard !Task.isCancelled else {
                    print("[Gutter] Task cancelled (early)")
                    return
                }

                // Detect repo root (cached after first call)
                if repoRoot == nil {
                    repoRoot = try await GitRepoDetector.detectRepoRoot(forFile: fileURL)
                    print("[Gutter] Detected repo root: \(repoRoot?.path ?? "nil")")
                    setupGitIndexWatcher()
                    setupGitHeadWatcher()
                    setupGitBranchRefWatcher()
                }

                guard let root = repoRoot else {
                    print("[Gutter] No repo root, skipping git changes")
                    gitChanges = nil
                    return
                }

                // Check for cancellation before expensive git operation
                guard !Task.isCancelled else {
                    print("[Gutter] Task cancelled (before git)")
                    return
                }

                let changes = try await GitDiffParser.parseChanges(forFile: fileURL, repoRoot: root)

                // Check for cancellation before applying result
                guard !Task.isCancelled else {
                    print("[Gutter] Task cancelled (after git)")
                    return
                }

                print("[Gutter] Got changes for \(fileURL.lastPathComponent): " +
                      "\(changes.addedRanges.count) added, \(changes.modifiedRanges.count) modified, " +
                      "\(changes.deletedAnchors.count) deleted")

                // Only update if changed to avoid redundant SwiftUI updates
                if gitChanges != changes {
                    gitChanges = changes
                } else {
                    print("[Gutter] Changes unchanged, skipping update")
                }
            } catch {
                // Only set nil if not cancelled
                guard !Task.isCancelled else {
                    print("[Gutter] Task cancelled (in catch)")
                    return
                }
                print("[Gutter] Error detecting changes: \(error)")
                gitChanges = nil
            }
        }
    }

    func handleCheckboxToggle(line: Int, checked: Bool) {
        guard let fileContent = try? String(contentsOf: fileURL, encoding: .utf8) else { return }

        var lines = fileContent.components(separatedBy: "\n")
        let index = line - 1

        guard index >= 0 && index < lines.count else { return }

        let currentLine = lines[index]
        let newLine: String

        if checked {
            newLine = currentLine
                .replacingOccurrences(of: "- [ ]", with: "- [x]")
                .replacingOccurrences(of: "* [ ]", with: "* [x]")
                .replacingOccurrences(of: "+ [ ]", with: "+ [x]")
        } else {
            newLine = currentLine
                .replacingOccurrences(of: "- [x]", with: "- [ ]")
                .replacingOccurrences(of: "- [X]", with: "- [ ]")
                .replacingOccurrences(of: "* [x]", with: "* [ ]")
                .replacingOccurrences(of: "* [X]", with: "* [ ]")
                .replacingOccurrences(of: "+ [x]", with: "+ [ ]")
                .replacingOccurrences(of: "+ [X]", with: "+ [ ]")
        }

        guard newLine != currentLine else { return }

        lines[index] = newLine
        let newContent = lines.joined(separator: "\n")

        do {
            try newContent.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            print("Failed to save file: \(error)")
        }
    }
}

import Foundation
import Observation
import RedmarginLib
import RedmarginCore

@MainActor
@Observable
class DocumentState {
    var content: String
    var gitChanges: GitChangeResult?
    var isRefreshing: Bool = false
    var refreshToken: Int = 0  // Sole purpose: bust image cache in MarkdownWebView
    private(set) var fileURL: URL

    @ObservationIgnored private let fileProvider: FileProvider

    @ObservationIgnored private var fileWatchToken: WatchToken?
    @ObservationIgnored private var gitWatchToken: WatchToken?
    @ObservationIgnored private var isWritingFile = false

    @ObservationIgnored private var repoRoot: String?
    @ObservationIgnored private var gitChangeTask: Task<Void, Never>?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?

    init(content: String, fileURL: URL, fileProvider: FileProvider = LocalFileProvider()) {
        self.content = content
        self.fileURL = fileURL
        self.fileProvider = fileProvider
        Task {
            await setupFileWatcher()
            await detectGitChanges()
        }
    }

    deinit {
        let provider = fileProvider
        let fToken = fileWatchToken
        let gToken = gitWatchToken
        Task {
            if let token = fToken { await provider.unwatch(token) }
            if let token = gToken { await provider.unwatch(token) }
        }
    }

    private func setupFileWatcher() async {
        // Unwatch old if any
        if let token = fileWatchToken { await fileProvider.unwatch(token) }

        fileWatchToken = await fileProvider.watchFile(at: fileURL.path) { [weak self] in
            Task { @MainActor in
                self?.reloadContent()
            }
        }
    }

    private func reloadContent() {
        // Skip reload if we're writing the file ourselves (prevents race condition)
        guard !isWritingFile else {
            print("[DocumentState] Skipping reload during self-initiated write")
            return
        }

        print("[DocumentState] reloadContent called for \(fileURL.lastPathComponent)")

        // Cancel any in-flight reload to avoid out-of-order updates
        reloadTask?.cancel()
        reloadTask = Task {
            do {
                let newContent = try await fileProvider.readFile(at: fileURL.path)
                guard !Task.isCancelled else { return }
                guard newContent != content else {
                    print("[DocumentState] Content unchanged, skipping update")
                    return
                }
                print("[DocumentState] Content changed, updating (\(newContent.count) chars)")
                content = newContent
                await detectGitChanges()
            } catch {
                if !Task.isCancelled {
                    print("[DocumentState] Failed to read file: \(error)")
                }
            }
        }
    }

    func refresh() {
        isRefreshing = true
        refreshToken += 1  // Bust image cache
        Task {
            if let newContent = try? await fileProvider.readFile(at: fileURL.path) {
                await MainActor.run {
                    content = newContent
                }
            }
            await detectGitChanges()

            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
            await MainActor.run {
                self.isRefreshing = false
            }
        }
    }

    /// Loads a different file in the same window
    func loadFile(at url: URL) async throws {
        // Read the new file content
        let newContent = try await fileProvider.readFile(at: url.path)

        // Update file URL and content
        fileURL = url
        content = newContent
        gitChanges = nil
        repoRoot = nil
        refreshToken += 1

        // Reset watchers for the new file
        await setupFileWatcher()
        await detectGitChanges()
    }

    private func detectGitChanges() async {
        print("[Gutter] detectGitChanges called for \(fileURL.lastPathComponent)")

        gitChangeTask?.cancel()

        gitChangeTask = Task { @MainActor in
            do {
                guard !Task.isCancelled else { return }

                if repoRoot == nil {
                    repoRoot = try await fileProvider.detectGitRepo(for: fileURL.path)
                    print("[Gutter] Detected repo root: \(repoRoot ?? "nil")")

                    if let root = repoRoot {
                        await setupGitWatcher(root: root)
                    }
                }

                guard let root = repoRoot else {
                    gitChanges = nil
                    return
                }

                guard !Task.isCancelled else { return }

                let changes = try await fileProvider.gitDiff(for: fileURL.path, repoRoot: root)

                guard !Task.isCancelled else { return }

                if gitChanges != changes {
                    gitChanges = changes
                }
            } catch {
                if !Task.isCancelled {
                    print("[Gutter] Error detecting changes: \(error)")
                    gitChanges = nil
                }
            }
        }
    }

    private func setupGitWatcher(root: String) async {
        if let token = gitWatchToken { await fileProvider.unwatch(token) }

        gitWatchToken = await fileProvider.watchGitRepo(at: root) { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                await self.detectGitChanges()
            }
        }
    }

    func handleCheckboxToggle(line: Int, checked: Bool) {
        isWritingFile = true

        Task {
            defer {
                Task { @MainActor in
                    self.isWritingFile = false
                }
            }

            // Always read from disk first for safety
            guard let fileContent = try? await fileProvider.readFile(at: fileURL.path) else {
                return
            }

            var lines = fileContent.components(separatedBy: "\n")
            let index = line - 1

            guard index >= 0 && index < lines.count else { return }

            let currentLine = lines[index]
            let newLine = toggleCheckbox(in: currentLine, checked: checked)

            guard newLine != currentLine else { return }

            lines[index] = newLine
            let newContent = lines.joined(separator: "\n")

            do {
                // Write to disk FIRST
                try await fileProvider.writeFile(at: fileURL.path, content: newContent)
                // Only update in-memory content after successful write
                await MainActor.run {
                    self.content = newContent
                }
            } catch {
                print("Failed to save file: \(error)")
            }
        }
    }
}

import Foundation
import RedmarginLib
import RedmarginCore

@MainActor
class DocumentState: ObservableObject {
    @Published var content: String
    @Published var gitChanges: GitChangeResult?
    @Published var isRefreshing: Bool = false
    @Published var refreshToken: Int = 0  // Incremented on refresh to bust image cache

    // We keep fileURL for now as it might be used by UI or other parts
    let fileURL: URL
    private let fileProvider: FileProvider

    private var fileWatchToken: WatchToken?
    private var gitWatchToken: WatchToken?
    private var isWritingFile = false

    private var repoRoot: String?
    private var gitChangeTask: Task<Void, Never>?

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
        Task {
            do {
                let newContent = try await fileProvider.readFile(at: fileURL.path)
                // Update on MainActor
                await MainActor.run {
                    guard newContent != content else {
                        print("[DocumentState] Content unchanged, skipping update")
                        return
                    }
                    print("[DocumentState] Content changed, updating (\(newContent.count) chars)")
                    content = newContent
                    Task {
                        await detectGitChanges()
                    }
                }
            } catch {
                print("[DocumentState] Failed to read file: \(error)")
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

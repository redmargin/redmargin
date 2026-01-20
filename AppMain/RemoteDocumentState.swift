import Foundation
import RedmarginLib
import RedmarginCore

@MainActor
class RemoteDocumentState: ObservableObject {
    @Published var content: String
    @Published var gitChanges: GitChangeResult?
    @Published var isRefreshing: Bool = false
    @Published var connectionState: SSHConnectionState = .connected

    let location: RemoteLocation
    private let fileProvider: RemoteFileProvider

    private var fileWatchToken: WatchToken?
    private var gitWatchToken: WatchToken?

    private var repoRoot: String?
    private var gitChangeTask: Task<Void, Never>?

    init(content: String, location: RemoteLocation, fileProvider: RemoteFileProvider) {
        self.content = content
        self.location = location
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
        if let token = fileWatchToken { await fileProvider.unwatch(token) }

        fileWatchToken = await fileProvider.watchFile(at: location.path) { [weak self] in
            Task { @MainActor in
                self?.reloadContent()
            }
        }
    }

    private func reloadContent() {
        print("[RemoteDocumentState] reloadContent called for \(location.displayString)")
        Task {
            do {
                let newContent = try await fileProvider.readFile(at: location.path)
                await MainActor.run {
                    guard newContent != content else {
                        print("[RemoteDocumentState] Content unchanged, skipping update")
                        return
                    }
                    print("[RemoteDocumentState] Content changed, updating (\(newContent.count) chars)")
                    content = newContent
                    Task {
                        await detectGitChanges()
                    }
                }
            } catch {
                print("[RemoteDocumentState] Failed to read file: \(error)")
            }
        }
    }

    func refresh() {
        isRefreshing = true
        Task {
            if let newContent = try? await fileProvider.readFile(at: location.path) {
                await MainActor.run {
                    content = newContent
                }
            }
            await detectGitChanges()

            try? await Task.sleep(nanoseconds: 300_000_000)
            await MainActor.run {
                self.isRefreshing = false
            }
        }
    }

    private func detectGitChanges() async {
        print("[RemoteGutter] detectGitChanges called for \(location.displayString)")

        gitChangeTask?.cancel()

        gitChangeTask = Task { @MainActor in
            do {
                guard !Task.isCancelled else { return }

                if repoRoot == nil {
                    repoRoot = try await fileProvider.detectGitRepo(for: location.path)
                    print("[RemoteGutter] Detected repo root: \(repoRoot ?? "nil")")

                    if let root = repoRoot {
                        await setupGitWatcher(root: root)
                    }
                }

                guard let root = repoRoot else {
                    gitChanges = nil
                    return
                }

                guard !Task.isCancelled else { return }

                let changes = try await fileProvider.gitDiff(for: location.path, repoRoot: root)

                guard !Task.isCancelled else { return }

                if gitChanges != changes {
                    gitChanges = changes
                }
            } catch {
                if !Task.isCancelled {
                    print("[RemoteGutter] Error detecting changes: \(error)")
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
        // Optimistic UI - update locally first
        var lines = content.components(separatedBy: "\n")
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

        // Update locally immediately (optimistic)
        let oldContent = content
        content = newContent

        // Send to server
        Task {
            do {
                try await fileProvider.writeFile(at: location.path, content: newContent)
            } catch {
                print("[RemoteDocumentState] Failed to save checkbox toggle: \(error)")
                // Revert on failure
                await MainActor.run {
                    content = oldContent
                }
            }
        }
    }
}

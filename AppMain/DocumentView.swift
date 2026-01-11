import SwiftUI
import RedmarginLib
import os.log

private let logger = Logger(subsystem: "com.redmargin.app", category: "DocumentView")

class FileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let url: URL
    private let onChange: () -> Void
    private let eventMask: DispatchSource.FileSystemEvent

    init?(url: URL, writeOnly: Bool = false, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        // writeOnly excludes .attrib to avoid loops when file is read (atime updates)
        self.eventMask = writeOnly ? [.write, .rename, .delete] : [.write, .rename, .delete, .attrib]
        guard startWatching() else {
            print("[FileWatcher] Failed to start watching: \(url.path)")
            return nil
        }
        print("[FileWatcher] Started watching: \(url.path)")
    }

    private func startWatching() -> Bool {
        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            print("[FileWatcher] Failed to open: \(url.path)")
            return false
        }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: eventMask,
            queue: .main
        )

        source?.setEventHandler { [weak self] in
            guard let self = self else { return }
            let events = self.source?.data ?? []
            print("[FileWatcher] Event on \(self.url.lastPathComponent): \(events)")

            // For rename/delete (atomic writes), restart the watcher
            if events.contains(.rename) || events.contains(.delete) {
                self.restartWatching()
            } else {
                self.onChange()
            }
        }

        // Don't close fd in cancel handler - we manage it explicitly
        source?.setCancelHandler { }

        source?.resume()
        return true
    }

    private func restartWatching() {
        // Cancel old source and close old fd BEFORE opening new one
        source?.cancel()
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }

        // Delay to let file system settle after atomic write
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            if self.startWatching() {
                print("[FileWatcher] Restarted watching: \(self.url.path)")
                self.onChange()
            } else {
                print("[FileWatcher] Failed to restart watching: \(self.url.path)")
            }
        }
    }

    deinit {
        source?.cancel()
        if fileDescriptor >= 0 {
            close(fileDescriptor)
        }
    }
}

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

struct DocumentWindowContent: View {
    @StateObject private var state: DocumentState
    @StateObject private var findController = FindController()
    @State private var showLineNumbers: Bool
    @State private var showFindBar: Bool = false
    @State private var findBarFocusTrigger: UUID = UUID()
    let initialScrollPosition: Double
    let onScrollPositionChange: (Double) -> Void
    weak var appDelegate: AppDelegate?

    var fileURL: URL { state.fileURL }

    init(
        content: String,
        fileURL: URL,
        initialScrollPosition: Double = 0,
        showLineNumbers: Bool = false,
        appDelegate: AppDelegate? = nil,
        onScrollPositionChange: @escaping (Double) -> Void = { _ in }
    ) {
        _state = StateObject(wrappedValue: DocumentState(content: content, fileURL: fileURL))
        _showLineNumbers = State(initialValue: showLineNumbers)
        self.initialScrollPosition = initialScrollPosition
        self.appDelegate = appDelegate
        self.onScrollPositionChange = onScrollPositionChange
    }

    var body: some View {
        ZStack(alignment: .top) {
            MarkdownWebView(
                markdown: state.content,
                fileURL: fileURL,
                onCheckboxToggle: state.handleCheckboxToggle,
                onScrollPositionChange: onScrollPositionChange,
                initialScrollPosition: initialScrollPosition,
                showLineNumbers: showLineNumbers,
                gitChanges: state.gitChanges,
                findController: findController
            )

            if state.isRefreshing {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        ProgressView()
                            .scaleEffect(0.8)
                            .padding(8)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        Spacer()
                    }
                    Spacer()
                }
            }

            if showFindBar {
                FindBar(
                    searchText: $findController.searchText,
                    isVisible: $showFindBar,
                    matchCount: findController.matchCount,
                    currentMatch: findController.currentMatch,
                    focusTrigger: findBarFocusTrigger,
                    onFindNext: { findController.findNext() },
                    onFindPrevious: { findController.findPrevious() },
                    onDismiss: { dismissFindBar() }
                )
            }
        }
        .frame(minWidth: 500, idealWidth: 750, minHeight: 400, idealHeight: 1000)
        .onReceive(NotificationCenter.default.publisher(for: .toggleLineNumbers)) { _ in
            if isKeyWindow {
                showLineNumbers.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshDocument)) { _ in
            if isKeyWindow {
                state.refresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showFindBar)) { _ in
            if isKeyWindow {
                showFindBar = true
                findBarFocusTrigger = UUID()  // Trigger refocus
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .findNext)) { _ in
            if isKeyWindow && showFindBar {
                findController.findNext()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .findPrevious)) { _ in
            if isKeyWindow && showFindBar {
                findController.findPrevious()
            }
        }
        .onChange(of: showLineNumbers) { _, newValue in
            appDelegate?.saveLineNumbersVisible(newValue, for: fileURL)
        }
        .onChange(of: findController.searchText) { _, newValue in
            findController.find(newValue)
        }
    }

    private var isKeyWindow: Bool {
        guard let window = NSApp.keyWindow,
              let hostingController = window.contentViewController as? NSHostingController<DocumentWindowContent> else {
            return false
        }
        return hostingController.rootView.fileURL == fileURL
    }

    private func dismissFindBar() {
        showFindBar = false
        findController.clearFind()
    }
}

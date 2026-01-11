import SwiftUI
import RedmarginLib

class FileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let url: URL
    private let onChange: () -> Void

    init?(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        guard startWatching() else { return nil }
    }

    private func startWatching() -> Bool {
        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return false }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete, .attrib],
            queue: .main
        )

        source?.setEventHandler { [weak self] in
            guard let self = self else { return }
            let events = self.source?.data ?? []

            // For rename/delete (atomic writes), restart the watcher
            if events.contains(.rename) || events.contains(.delete) {
                self.restartWatching()
            }

            self.onChange()
        }

        source?.setCancelHandler { [weak self] in
            if let desc = self?.fileDescriptor, desc >= 0 {
                close(desc)
            }
        }

        source?.resume()
        return true
    }

    private func restartWatching() {
        source?.cancel()
        // Small delay to let the file system settle after atomic write
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self else { return }
            if self.startWatching() {
                // Check if content changed while watcher was down
                self.onChange()
            }
        }
    }

    deinit {
        source?.cancel()
    }
}

class DocumentState: ObservableObject {
    @Published var content: String
    @Published var gitChanges: GitChangeResult?
    @Published var isRefreshing: Bool = false
    let fileURL: URL
    private var fileWatcher: FileWatcher?
    private var gitIndexWatcher: FileWatcher?
    private var repoRoot: URL?

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
        gitIndexWatcher = FileWatcher(url: indexURL) { [weak self] in
            self?.detectGitChanges()
        }
    }

    private func reloadContent() {
        guard let newContent = try? String(contentsOf: fileURL, encoding: .utf8),
              newContent != content else { return }
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
        Task { @MainActor in
            do {
                // Detect repo root (cached after first call)
                if repoRoot == nil {
                    repoRoot = try await GitRepoDetector.detectRepoRoot(forFile: fileURL)
                    print("[Gutter] Detected repo root: \(repoRoot?.path ?? "nil")")
                    setupGitIndexWatcher()
                }

                guard let root = repoRoot else {
                    print("[Gutter] No repo root, skipping git changes")
                    gitChanges = nil
                    return
                }

                let changes = try await GitDiffParser.parseChanges(forFile: fileURL, repoRoot: root)
                print("[Gutter] Got changes: \(changes.addedRanges.count) added, " +
                      "\(changes.modifiedRanges.count) modified, \(changes.deletedAnchors.count) deleted")
                gitChanges = changes
            } catch {
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
    @State private var showLineNumbers: Bool
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
        ZStack {
            MarkdownWebView(
                markdown: state.content,
                fileURL: fileURL,
                onCheckboxToggle: state.handleCheckboxToggle,
                onScrollPositionChange: onScrollPositionChange,
                initialScrollPosition: initialScrollPosition,
                showLineNumbers: showLineNumbers,
                gitChanges: state.gitChanges
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
        }
        .frame(minWidth: 500, idealWidth: 750, minHeight: 400, idealHeight: 1000)
        .onReceive(NotificationCenter.default.publisher(for: .toggleLineNumbers)) { _ in
            if let window = NSApp.keyWindow,
               let hostingController = window.contentViewController as? NSHostingController<DocumentWindowContent>,
               hostingController.rootView.fileURL == fileURL {
                showLineNumbers.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshDocument)) { _ in
            if let window = NSApp.keyWindow,
               let hostingController = window.contentViewController as? NSHostingController<DocumentWindowContent>,
               hostingController.rootView.fileURL == fileURL {
                state.refresh()
            }
        }
        .onChange(of: showLineNumbers) { _, newValue in
            appDelegate?.saveLineNumbersVisible(newValue, for: fileURL)
        }
    }
}

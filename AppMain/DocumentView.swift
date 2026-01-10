import SwiftUI
import RedmarginLib

class FileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private let fileDescriptor: Int32
    private let onChange: () -> Void

    init?(url: URL, onChange: @escaping () -> Void) {
        self.onChange = onChange
        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return nil }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )

        source?.setEventHandler { [weak self] in
            self?.onChange()
        }

        source?.setCancelHandler { [weak self] in
            if let desc = self?.fileDescriptor, desc >= 0 {
                close(desc)
            }
        }

        source?.resume()
    }

    deinit {
        source?.cancel()
    }
}

class DocumentState: ObservableObject {
    @Published var content: String
    let fileURL: URL
    private var fileWatcher: FileWatcher?

    init(content: String, fileURL: URL) {
        self.content = content
        self.fileURL = fileURL
        setupFileWatcher()
    }

    private func setupFileWatcher() {
        fileWatcher = FileWatcher(url: fileURL) { [weak self] in
            self?.reloadContent()
        }
    }

    private func reloadContent() {
        guard let newContent = try? String(contentsOf: fileURL, encoding: .utf8),
              newContent != content else { return }
        content = newContent
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
    @ObservedObject var state: DocumentState
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
        self.state = DocumentState(content: content, fileURL: fileURL)
        _showLineNumbers = State(initialValue: showLineNumbers)
        self.initialScrollPosition = initialScrollPosition
        self.appDelegate = appDelegate
        self.onScrollPositionChange = onScrollPositionChange
    }

    var body: some View {
        MarkdownWebView(
            markdown: state.content,
            fileURL: fileURL,
            onCheckboxToggle: state.handleCheckboxToggle,
            onScrollPositionChange: onScrollPositionChange,
            initialScrollPosition: initialScrollPosition,
            showLineNumbers: showLineNumbers
        )
        .frame(minWidth: 500, idealWidth: 750, minHeight: 400, idealHeight: 1000)
        .onReceive(NotificationCenter.default.publisher(for: .toggleLineNumbers)) { _ in
            if let window = NSApp.keyWindow,
               let hostingController = window.contentViewController as? NSHostingController<DocumentWindowContent>,
               hostingController.rootView.fileURL == fileURL {
                showLineNumbers.toggle()
            }
        }
        .onChange(of: showLineNumbers) { _, newValue in
            appDelegate?.saveLineNumbersVisible(newValue, for: fileURL)
        }
    }
}

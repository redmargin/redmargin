import SwiftUI
import RedmarginLib

struct DocumentWindowContent: View {
    @StateObject private var state: DocumentState
    @StateObject private var findController = FindController()
    @ObservedObject private var prefs = PreferencesManager.shared
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var showLineNumbers: Bool
    @State private var showFindBar: Bool = false
    @State private var findBarFocusTrigger: UUID = UUID()
    let initialScrollPosition: Double
    let onScrollPositionChange: (Double) -> Void
    weak var appDelegate: AppDelegate?

    var fileURL: URL { state.fileURL }

    private var effectiveTheme: String {
        switch prefs.theme {
        case .system:
            return systemColorScheme == .dark ? "dark" : "light"
        case .light:
            return "light"
        case .dark:
            return "dark"
        }
    }

    private var shouldShowGutter: Bool {
        // Show gutter if we have git changes (it's a repo), or if preference says show for non-repo
        if state.gitChanges != nil {
            return true
        }
        return prefs.gutterVisibilityForNonRepo == .showEmpty
    }

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
                findController: findController,
                theme: effectiveTheme,
                inlineCodeColor: prefs.inlineCodeColor.rawValue,
                allowRemoteImages: prefs.allowRemoteImages,
                showGutter: shouldShowGutter
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
        .onReceive(NotificationCenter.default.publisher(for: .printDocument)) { _ in
            if isKeyWindow {
                executePrint()
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

    private func executePrint() {
        guard let webView = findController.webView else { return }
        let printOperation = webView.printOperation(with: NSPrintInfo.shared)
        printOperation.showsPrintPanel = true
        printOperation.showsProgressPanel = true
        printOperation.run()
    }
}

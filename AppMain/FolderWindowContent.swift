import SwiftUI
import WebKit
import UserNotifications
import RedmarginLib
import RedmarginCore

struct FolderWindowContent: View {
    @StateObject private var fileTreeProvider: FileTreeProvider
    @StateObject private var findController = FindController()
    @ObservedObject private var prefs = PreferencesManager.shared
    @Environment(\.colorScheme) private var systemColorScheme

    @State private var selectedFileURL: URL?
    @State private var documentState: DocumentState?
    @State private var showSidebar: Bool = true
    @State private var sidebarWidth: CGFloat = 200
    @State private var showGutter: Bool
    @State private var showLineNumbers: Bool
    @State private var showGitIndicators: Bool
    @State private var showFindBar: Bool = false
    @State private var findBarFocusTrigger: UUID = UUID()
    @State private var isExporting: Bool = false

    let folderURL: URL
    weak var appDelegate: AppDelegate?

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

    init(
        folderURL: URL,
        showSidebar: Bool? = nil,
        sidebarWidth: CGFloat? = nil,
        appDelegate: AppDelegate? = nil
    ) {
        let prefs = PreferencesManager.shared
        self.folderURL = folderURL
        _fileTreeProvider = StateObject(wrappedValue: FileTreeProvider(rootDirectory: folderURL))
        _showSidebar = State(initialValue: showSidebar ?? true)
        _sidebarWidth = State(initialValue: sidebarWidth ?? 200)
        _showGutter = State(initialValue: prefs.showGutter)
        _showLineNumbers = State(initialValue: prefs.showLineNumbers)
        _showGitIndicators = State(initialValue: prefs.showGitIndicators)
        self.appDelegate = appDelegate
    }

    var body: some View {
        mainContent
            .frame(minWidth: 500, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
            .modifier(FolderNotificationModifiers(
                checkIsKeyWindow: { [self] in self.isKeyWindow },
                showSidebar: $showSidebar,
                showGutter: $showGutter,
                showLineNumbers: $showLineNumbers,
                showGitIndicators: $showGitIndicators,
                showFindBar: $showFindBar,
                findBarFocusTrigger: $findBarFocusTrigger,
                sidebarWidth: sidebarWidth,
                hasDocument: selectedFileURL != nil,
                onRefresh: { documentState?.refresh() },
                onFindNext: { findController.findNext() },
                onFindPrevious: { findController.findPrevious() },
                onPrint: executePrint,
                onExport: executeExport
            ))
            .onKeyPress(.escape) {
                guard showFindBar else { return .ignored }
                dismissFindBar()
                return .handled
            }
            .onAppear {
                setupExpandedFoldersPersistence()
            }
    }

    private func setupExpandedFoldersPersistence() {
        let settings = DocumentSettingsStorage.shared

        fileTreeProvider.onExpandedFoldersChange = { rootPath, expandedPaths in
            settings.saveExpandedFolders(expandedPaths, for: rootPath)
        }

        Task { @MainActor in
            while fileTreeProvider.isLoading {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }

            if let rootPath = fileTreeProvider.rootDirectory?.path {
                let expandedFolders = settings.loadExpandedFolders(for: rootPath)
                if !expandedFolders.isEmpty {
                    fileTreeProvider.applyExpandedFolders(expandedFolders)
                }
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        SidebarSplitView(
            sidebar: {
                SidebarView(
                    rootNodes: fileTreeProvider.rootNodes,
                    rootDirectory: fileTreeProvider.rootDirectory?.path,
                    currentFileURL: selectedFileURL ?? URL(fileURLWithPath: "/"),
                    isLoading: fileTreeProvider.isLoading,
                    onFileSelected: { url in
                        handleFileSelection(url)
                    },
                    onRefresh: {
                        fileTreeProvider.refresh()
                    }
                )
            },
            content: {
                contentArea
            },
            isSidebarVisible: $showSidebar,
            sidebarWidth: $sidebarWidth
        )
    }

    @ViewBuilder
    private var contentArea: some View {
        if let state = documentState {
            ZStack(alignment: .top) {
                MarkdownWebView(
                    markdown: state.content,
                    fileURL: state.fileURL,
                    onCheckboxToggle: state.handleCheckboxToggle,
                    onScrollPositionChange: { _ in },
                    onFirstRenderComplete: { },
                    initialScrollPosition: 0,
                    showLineNumbers: showLineNumbers,
                    gitChanges: state.gitChanges,
                    findController: findController,
                    theme: effectiveTheme,
                    inlineCodeColor: prefs.inlineCodeColor.rawValue,
                    allowRemoteImages: prefs.allowRemoteImages,
                    showGutter: showGutter,
                    showGitIndicators: showGitIndicators,
                    cacheBust: state.refreshToken
                )

                if state.isRefreshing || isExporting {
                    loadingOverlay
                }

                if showFindBar {
                    findBarView
                }
            }
        } else {
            welcomeView
        }
    }

    private var welcomeView: some View {
        ContentUnavailableView(
            "No Selection",
            systemImage: "doc.text",
            description: Text("Select a file from the sidebar")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingOverlay: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text(isExporting ? "Exporting PDF..." : "Refreshing...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                }
                .padding(24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 8)
                Spacer()
            }
            Spacer()
        }
    }

    private var findBarView: some View {
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

    private var isKeyWindow: Bool {
        guard let window = NSApp.keyWindow,
              let hostingController = window.contentViewController
                as? NSHostingController<FolderWindowContent> else {
            return false
        }
        return hostingController.rootView.folderURL == folderURL
    }

    private func dismissFindBar() {
        showFindBar = false
        findController.clearFind()
    }

    private func handleFileSelection(_ url: URL) {
        guard url != selectedFileURL else { return }

        if let existingState = documentState {
            // Navigate to new file in same window
            Task {
                do {
                    try await existingState.loadFile(at: url)
                    selectedFileURL = url
                    appDelegate?.updateFolderWindowFile(folder: folderURL, to: url)

                    // Update window title
                    if let window = NSApp.keyWindow {
                        window.title = url.displayPath
                    }
                } catch {
                    print("[FolderWindowContent] Failed to load file: \(error)")
                }
            }
        } else {
            // First file selection — create DocumentState
            let content = (try? String(contentsOf: url, encoding: .utf8)) ?? "Error loading file"
            documentState = DocumentState(content: content, fileURL: url)
            selectedFileURL = url
            appDelegate?.updateFolderWindowFile(folder: folderURL, to: url)

            // Update window title
            if let window = NSApp.keyWindow {
                window.title = url.displayPath
            }
        }
    }

    private func executePrint() {
        guard selectedFileURL != nil else { return }
        guard let webView = findController.webView,
              let window = NSApp.mainWindow ?? NSApp.keyWindow else { return }

        var classes: [String] = ["print-light-theme"]
        if !prefs.showGutter {
            classes.append("print-hide-gutter")
        }
        if !showLineNumbers {
            classes.append("print-hide-line-numbers")
        }

        let jsCommands: [String] = classes.map { "document.body.classList.add('\($0)');" }
        let prepareJS = jsCommands.joined()

        webView.evaluateJavaScript(prepareJS) { [weak webView] _, _ in
            guard let webView = webView else { return }

            webView.setValue(true, forKey: "drawsBackground")

            let printInfo = NSPrintInfo.shared
            printInfo.paperSize = NSSize(width: 595.28, height: 841.89)
            printInfo.topMargin = 56
            printInfo.bottomMargin = 56
            printInfo.leftMargin = self.prefs.printMargin
            printInfo.rightMargin = self.prefs.printMargin

            let printOperation = webView.printOperation(with: printInfo)
            if let state = self.documentState {
                printOperation.jobTitle = state.fileURL.deletingPathExtension().lastPathComponent
            }
            printOperation.showsPrintPanel = true
            printOperation.showsProgressPanel = true

            let handler = FolderPrintCompletionHandler(webView: webView, printClasses: classes)
            objc_setAssociatedObject(printOperation, "handler", handler, .OBJC_ASSOCIATION_RETAIN)

            printOperation.runModal(
                for: window,
                delegate: handler,
                didRun: #selector(FolderPrintCompletionHandler.printOperationDidRun(_:success:contextInfo:)),
                contextInfo: nil
            )
        }
    }

    private func executeExport() {
        guard selectedFileURL != nil else { return }
        guard let webView = findController.webView else { return }
        guard !isExporting else { return }

        isExporting = true
        let filename = documentState?.fileURL.deletingPathExtension().lastPathComponent ?? "export"

        PDFExporter.export(
            webView: webView,
            filename: filename,
            theme: effectiveTheme,
            printMargin: prefs.printMargin
        ) { result in
            DispatchQueue.main.async {
                self.isExporting = false
                switch result {
                case .success(let url):
                    let content = UNMutableNotificationContent()
                    content.title = "PDF Exported"
                    content.body = url.lastPathComponent
                    content.sound = .default
                    let request = UNNotificationRequest(
                        identifier: UUID().uuidString, content: content, trigger: nil
                    )
                    UNUserNotificationCenter.current().add(request)
                case .failure(let error):
                    guard let window = NSApp.keyWindow else { return }
                    let alert = NSAlert()
                    alert.messageText = "Export Failed"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.beginSheetModal(for: window)
                }
            }
        }
    }
}

// MARK: - View Modifiers

private struct FolderNotificationModifiers: ViewModifier {
    let checkIsKeyWindow: () -> Bool
    @Binding var showSidebar: Bool
    @Binding var showGutter: Bool
    @Binding var showLineNumbers: Bool
    @Binding var showGitIndicators: Bool
    @Binding var showFindBar: Bool
    @Binding var findBarFocusTrigger: UUID
    let sidebarWidth: CGFloat
    let hasDocument: Bool
    let onRefresh: () -> Void
    let onFindNext: () -> Void
    let onFindPrevious: () -> Void
    let onPrint: () -> Void
    let onExport: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
                if checkIsKeyWindow() {
                    toggleSidebarWithWindowResize()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleGutter)) { _ in
                if checkIsKeyWindow() && hasDocument { showGutter.toggle() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleLineNumbers)) { _ in
                if checkIsKeyWindow() && hasDocument { showLineNumbers.toggle() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleGitIndicators)) { _ in
                if checkIsKeyWindow() && hasDocument { showGitIndicators.toggle() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .refreshDocument)) { _ in
                if checkIsKeyWindow() && hasDocument { onRefresh() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showFindBar)) { _ in
                if checkIsKeyWindow() && hasDocument {
                    showFindBar = true
                    findBarFocusTrigger = UUID()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .findNext)) { _ in
                if checkIsKeyWindow() && hasDocument && showFindBar { onFindNext() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .findPrevious)) { _ in
                if checkIsKeyWindow() && hasDocument && showFindBar { onFindPrevious() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .printDocument)) { _ in
                if checkIsKeyWindow() && hasDocument { onPrint() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .exportToPDF)) { _ in
                if checkIsKeyWindow() && hasDocument { onExport() }
            }
    }

    private func toggleSidebarWithWindowResize() {
        guard let window = NSApp.keyWindow else {
            withAnimation(.easeInOut(duration: 0.2)) {
                showSidebar.toggle()
            }
            return
        }

        var frame = window.frame
        let delta = sidebarWidth + 1

        if showSidebar {
            frame.origin.x += delta
            frame.size.width -= delta
        } else {
            frame.origin.x -= delta
            frame.size.width += delta
        }

        if let screen = window.screen {
            let visibleFrame = screen.visibleFrame
            if frame.origin.x < visibleFrame.origin.x {
                frame.origin.x = visibleFrame.origin.x
            }
            if frame.maxX > visibleFrame.maxX {
                frame.origin.x = visibleFrame.maxX - frame.size.width
            }
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            showSidebar.toggle()
        }
        window.setFrame(frame, display: true, animate: true)
    }
}

private class FolderPrintCompletionHandler: NSObject {
    private let webView: WKWebView
    private let printClasses: [String]

    init(webView: WKWebView, printClasses: [String]) {
        self.webView = webView
        self.printClasses = printClasses
        super.init()
    }

    @objc func printOperationDidRun(
        _ operation: NSPrintOperation,
        success: Bool,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        webView.setValue(false, forKey: "drawsBackground")
        let cleanupJS = printClasses.map { "document.body.classList.remove('\($0)');" }.joined()
        webView.evaluateJavaScript(cleanupJS, completionHandler: nil)
    }
}

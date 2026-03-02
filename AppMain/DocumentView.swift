import SwiftUI
import WebKit
import UserNotifications
import RedmarginLib
import RedmarginCore

struct DocumentWindowContent: View {
    @State private var state: DocumentState
    @StateObject private var findController = FindController()
    @StateObject private var fileTreeProvider: FileTreeProvider
    @ObservedObject private var prefs = PreferencesManager.shared
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var showSidebar: Bool
    @State private var sidebarWidth: CGFloat
    @State private var showGutter: Bool
    @State private var showLineNumbers: Bool
    @State private var showGitIndicators: Bool
    @State private var showFindBar: Bool = false
    @State private var findBarFocusTrigger: UUID = UUID()
    @State private var isExporting: Bool = false
    let initialScrollPosition: Double
    let onScrollPositionChange: (Double) -> Void
    weak var appDelegate: AppDelegate?

    /// Stored file URL for identification (avoids StateObject access issues)
    let storedFileURL: URL

    var fileURL: URL { storedFileURL }

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
        content: String,
        fileURL: URL,
        initialScrollPosition: Double = 0,
        showSidebar: Bool? = nil,
        sidebarWidth: CGFloat? = nil,
        showGutter: Bool? = nil,
        showLineNumbers: Bool? = nil,
        showGitIndicators: Bool? = nil,
        appDelegate: AppDelegate? = nil,
        onScrollPositionChange: @escaping (Double) -> Void = { _ in }
    ) {
        let prefs = PreferencesManager.shared
        self.storedFileURL = fileURL
        _state = State(initialValue: DocumentState(content: content, fileURL: fileURL))
        _fileTreeProvider = StateObject(wrappedValue: FileTreeProvider(currentFileURL: fileURL))
        _showSidebar = State(initialValue: showSidebar ?? false)
        _sidebarWidth = State(initialValue: sidebarWidth ?? 200)
        _showGutter = State(initialValue: showGutter ?? prefs.showGutter)
        _showLineNumbers = State(initialValue: showLineNumbers ?? prefs.showLineNumbers)
        _showGitIndicators = State(initialValue: showGitIndicators ?? prefs.showGitIndicators)
        self.initialScrollPosition = initialScrollPosition
        self.appDelegate = appDelegate
        self.onScrollPositionChange = onScrollPositionChange
    }

    var body: some View {
        mainContent
            .frame(minWidth: 500, idealWidth: 750, minHeight: 400, idealHeight: 1000)
            .modifier(NotificationModifiers(
                checkIsKeyWindow: { [self] in self.isKeyWindow },
                showSidebar: $showSidebar,
                showGutter: $showGutter,
                showLineNumbers: $showLineNumbers,
                showGitIndicators: $showGitIndicators,
                showFindBar: $showFindBar,
                findBarFocusTrigger: $findBarFocusTrigger,
                sidebarWidth: sidebarWidth,
                onRefresh: {
                    state.refresh()
                    if showSidebar { fileTreeProvider.refresh() }
                },
                onFindNext: { findController.findNext() },
                onFindPrevious: { findController.findPrevious() },
                onPrint: executePrint,
                onExport: executeExport
            ))
            .modifier(PersistenceModifiers(
                fileURL: state.fileURL,
                showGutter: showGutter,
                showLineNumbers: showLineNumbers,
                showGitIndicators: showGitIndicators,
                showSidebar: showSidebar,
                sidebarWidth: sidebarWidth,
                findSearchText: findController.searchText,
                onFind: { findController.find($0) }
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

        // Set up callback for saving expanded folders
        fileTreeProvider.onExpandedFoldersChange = { rootPath, expandedPaths in
            settings.saveExpandedFolders(expandedPaths, for: rootPath)
        }

        // Load and apply saved expanded folders once rootDirectory is available
        Task { @MainActor in
            // Wait for FileTreeProvider to finish loading
            while fileTreeProvider.isLoading {
                try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
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
                    currentFileURL: state.fileURL,
                    isLoading: fileTreeProvider.isLoading,
                    onFileSelected: { url in
                        handleFileSelection(url)
                    },
                    onRefresh: {
                        state.refresh()
                        fileTreeProvider.refresh()
                    }
                )
            },
            content: {
                documentContent
            },
            isSidebarVisible: $showSidebar,
            sidebarWidth: $sidebarWidth
        )
    }

    @ViewBuilder
    private var documentContent: some View {
        ZStack(alignment: .top) {
            markdownView

            if state.isRefreshing || isExporting {
                loadingOverlay
            }

            if showFindBar {
                findBarView
            }
        }
    }

    private var markdownView: some View {
        MarkdownWebView(
            markdown: state.content,
            fileURL: state.fileURL,
            onCheckboxToggle: state.handleCheckboxToggle,
            onScrollPositionChange: onScrollPositionChange,
            onFirstRenderComplete: { [state] in
                NotificationCenter.default.post(
                    name: .windowContentReady,
                    object: nil,
                    userInfo: ["fileURL": state.fileURL as Any]
                )
            },
            initialScrollPosition: initialScrollPosition,
            showLineNumbers: showLineNumbers,
            gitChanges: state.gitChanges,
            findController: findController,
            theme: effectiveTheme,
            inlineCodeColor: prefs.inlineCodeColor.rawValue,
            allowRemoteImages: prefs.allowRemoteImages,
            showGutter: showGutter,
            showGitIndicators: showGitIndicators,
            textWidth: prefs.textWidth.rawValue,
            contentWidth: prefs.contentWidth.rawValue,
            cacheBust: state.refreshToken
        )
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
              let hostingController = window.contentViewController as? NSHostingController<DocumentWindowContent> else {
            return false
        }
        return hostingController.rootView.fileURL == fileURL
    }

    private func dismissFindBar() {
        showFindBar = false
        findController.clearFind()
    }

    private func handleFileSelection(_ url: URL) {
        let oldURL = state.fileURL
        guard url != oldURL else { return }

        Task {
            do {
                try await state.loadFile(at: url)
                appDelegate?.updateWindowTracking(from: oldURL, to: url)

                // Save current view settings for the new file
                let settings = DocumentSettingsStorage.shared
                settings.saveSidebarVisible(showSidebar, for: url)
                settings.saveSidebarWidth(sidebarWidth, for: url)
                settings.saveGutterVisible(showGutter, for: url)
                settings.saveLineNumbersVisible(showLineNumbers, for: url)
                settings.saveGitIndicatorsVisible(showGitIndicators, for: url)
            } catch {
                print("[DocumentView] Failed to load file: \(error)")
            }
        }
    }

    private func executePrint() {
        guard let webView = findController.webView,
              let window = NSApp.mainWindow ?? NSApp.keyWindow else { return }

        // Build print CSS classes based on current document settings
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
            printInfo.paperSize = NSSize(width: 595.28, height: 841.89) // A4
            printInfo.topMargin = 56
            printInfo.bottomMargin = 56
            printInfo.leftMargin = self.prefs.printMargin
            printInfo.rightMargin = self.prefs.printMargin

            let printOperation = webView.printOperation(with: printInfo)
            printOperation.jobTitle = self.state.fileURL.deletingPathExtension().lastPathComponent
            printOperation.showsPrintPanel = true
            printOperation.showsProgressPanel = true

            let handler = PrintCompletionHandler(webView: webView, printClasses: classes)
            objc_setAssociatedObject(printOperation, "handler", handler, .OBJC_ASSOCIATION_RETAIN)

            printOperation.runModal(
                for: window,
                delegate: handler,
                didRun: #selector(PrintCompletionHandler.printOperationDidRun(_:success:contextInfo:)),
                contextInfo: nil
            )
        }
    }

    private func executeExport() {
        guard let webView = findController.webView else { return }
        guard !isExporting else { return }

        isExporting = true
        let filename = state.fileURL.deletingPathExtension().lastPathComponent

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
                    self.showExportSuccessNotification(url: url)
                case .failure(let error):
                    self.showExportErrorAlert(error: error)
                }
            }
        }
    }

    private func showExportSuccessNotification(url: URL) {
        let content = UNMutableNotificationContent()
        content.title = "PDF Exported"
        content.body = url.lastPathComponent
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    private func showExportErrorAlert(error: Error) {
        guard let window = NSApp.keyWindow else { return }

        let alert = NSAlert()
        alert.messageText = "Export Failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window)
    }
}

private class PrintCompletionHandler: NSObject {
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

// MARK: - View Modifiers

private struct NotificationModifiers: ViewModifier {
    let checkIsKeyWindow: () -> Bool
    @Binding var showSidebar: Bool
    @Binding var showGutter: Bool
    @Binding var showLineNumbers: Bool
    @Binding var showGitIndicators: Bool
    @Binding var showFindBar: Bool
    @Binding var findBarFocusTrigger: UUID
    let sidebarWidth: CGFloat
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
                if checkIsKeyWindow() { showGutter.toggle() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleLineNumbers)) { _ in
                if checkIsKeyWindow() { showLineNumbers.toggle() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleGitIndicators)) { _ in
                if checkIsKeyWindow() { showGitIndicators.toggle() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .refreshDocument)) { _ in
                if checkIsKeyWindow() { onRefresh() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showFindBar)) { _ in
                if checkIsKeyWindow() {
                    showFindBar = true
                    findBarFocusTrigger = UUID()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .findNext)) { _ in
                if checkIsKeyWindow() && showFindBar { onFindNext() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .findPrevious)) { _ in
                if checkIsKeyWindow() && showFindBar { onFindPrevious() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .printDocument)) { _ in
                if checkIsKeyWindow() { onPrint() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .exportToPDF)) { _ in
                if checkIsKeyWindow() { onExport() }
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
        let delta = sidebarWidth + 1  // +1 for divider

        if showSidebar {
            // Hiding sidebar - shrink window
            frame.origin.x += delta
            frame.size.width -= delta
        } else {
            // Showing sidebar - expand window
            frame.origin.x -= delta
            frame.size.width += delta
        }

        // Ensure window stays on screen
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

private struct PersistenceModifiers: ViewModifier {
    let fileURL: URL
    let showGutter: Bool
    let showLineNumbers: Bool
    let showGitIndicators: Bool
    let showSidebar: Bool
    let sidebarWidth: CGFloat
    let findSearchText: String
    let onFind: (String) -> Void

    private let settings = DocumentSettingsStorage.shared

    func body(content: Content) -> some View {
        content
            .onChange(of: showGutter) { _, newValue in
                settings.saveGutterVisible(newValue, for: fileURL)
            }
            .onChange(of: showLineNumbers) { _, newValue in
                settings.saveLineNumbersVisible(newValue, for: fileURL)
            }
            .onChange(of: showGitIndicators) { _, newValue in
                settings.saveGitIndicatorsVisible(newValue, for: fileURL)
            }
            .onChange(of: showSidebar) { _, newValue in
                settings.saveSidebarVisible(newValue, for: fileURL)
            }
            .onChange(of: sidebarWidth) { _, newValue in
                settings.saveSidebarWidth(newValue, for: fileURL)
            }
            .onChange(of: findSearchText) { _, newValue in
                onFind(newValue)
            }
    }
}

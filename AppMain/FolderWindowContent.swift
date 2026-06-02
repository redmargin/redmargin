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
    @State private var textWidth: String
    @State private var contentWidth: String
    @State private var showHiddenFiles: Bool
    @State private var showFindBar: Bool = false
    @State private var findBarFocusTrigger: UUID = UUID()
    @State private var isExporting: Bool = false
    @State private var loadFileTask: Task<Void, Never>?

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

    private let initialSelectedFile: URL?

    init(
        folderURL: URL,
        initialSelectedFile: URL? = nil,
        showSidebar: Bool? = nil,
        sidebarWidth: CGFloat? = nil,
        showHiddenFiles: Bool? = nil,
        appDelegate: AppDelegate? = nil
    ) {
        let prefs = PreferencesManager.shared
        self.folderURL = folderURL
        self.initialSelectedFile = initialSelectedFile
        let savedExpanded = DocumentSettingsStorage.shared.loadExpandedFolders(for: folderURL.path)
        _fileTreeProvider = StateObject(wrappedValue: FileTreeProvider(
            rootDirectory: folderURL, expandedFolders: savedExpanded
        ))
        _showSidebar = State(initialValue: showSidebar ?? true)
        _sidebarWidth = State(initialValue: sidebarWidth ?? 200)
        _showHiddenFiles = State(initialValue: showHiddenFiles ?? prefs.showHiddenFiles)
        _showGutter = State(initialValue: prefs.showGutter)
        _showLineNumbers = State(initialValue: prefs.showLineNumbers)
        _showGitIndicators = State(initialValue: prefs.showGitIndicators)
        _textWidth = State(initialValue: prefs.textWidth.rawValue)
        _contentWidth = State(initialValue: prefs.contentWidth.rawValue)
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
                showHiddenFiles: $showHiddenFiles,
                textWidth: $textWidth,
                contentWidth: $contentWidth,
                showFindBar: $showFindBar,
                findBarFocusTrigger: $findBarFocusTrigger,
                sidebarWidth: sidebarWidth,
                hasDocument: selectedFileURL != nil,
                onRefresh: {
                    documentState?.refresh()
                    if showSidebar { fileTreeProvider.refresh() }
                },
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
            .onChange(of: showHiddenFiles) { _, newValue in
                DocumentSettingsStorage.shared.saveHiddenFilesVisible(newValue, for: folderURL)
                fileTreeProvider.showHiddenFiles = newValue
            }
            .onChange(of: prefs.showSidebarGitStatus) { _, newValue in
                fileTreeProvider.showGitStatus = newValue
            }
            .onAppear {
                fileTreeProvider.showHiddenFiles = showHiddenFiles
                fileTreeProvider.showGitStatus = prefs.showSidebarGitStatus
                setupExpandedFoldersPersistence()
            }
            .onChange(of: showSidebar) { _, newValue in
                DocumentSettingsStorage.shared.saveSidebarVisible(newValue, for: folderURL)
            }
            .onChange(of: sidebarWidth) { _, newValue in
                DocumentSettingsStorage.shared.saveSidebarWidth(newValue, for: folderURL)
            }
            .onChange(of: textWidth) { _, newValue in
                DocumentSettingsStorage.shared.saveTextWidth(newValue, for: folderURL)
            }
            .onChange(of: contentWidth) { _, newValue in
                DocumentSettingsStorage.shared.saveContentWidth(newValue, for: folderURL)
            }
            .onChange(of: findController.searchText) { _, newValue in
                findController.find(newValue)
            }
    }

    private func setupExpandedFoldersPersistence() {
        let settings = DocumentSettingsStorage.shared

        // Save callback — persists expansion changes to UserDefaults
        fileTreeProvider.onExpandedFoldersChange = { rootPath, expandedPaths in
            settings.saveExpandedFolders(expandedPaths, for: rootPath)
        }

        // Restore previously selected file once tree is ready
        if let fileURL = initialSelectedFile,
           FileManager.default.fileExists(atPath: fileURL.path) {
            Task { @MainActor in
                while fileTreeProvider.isLoading {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
                handleFileSelection(fileURL)
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
                        documentState?.refresh()
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
                    onScrollPositionChange: { position in
                        DocumentSettingsStorage.shared.saveScrollPosition(position, for: state.fileURL)
                    },
                    onFirstRenderComplete: { },
                    initialScrollPosition: DocumentSettingsStorage.shared.loadScrollPosition(for: state.fileURL),
                    showLineNumbers: showLineNumbers,
                    gitChanges: state.gitChanges,
                    findController: findController,
                    theme: effectiveTheme,
                    inlineCodeColor: prefs.inlineCodeColor.rawValue,
                    allowRemoteImages: prefs.allowRemoteImages,
                    showGutter: showGutter,
                    showGitIndicators: showGitIndicators,
                    textWidth: textWidth,
                    contentWidth: contentWidth,
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
            // Cancel any in-flight load before starting a new one
            loadFileTask?.cancel()
            loadFileTask = Task {
                do {
                    try await existingState.loadFile(at: url)
                    // Set selectedFileURL AFTER loadFile completes so the @State
                    // change triggers a re-render that picks up the new content.
                    // (documentState is @State, not @ObservedObject, so SwiftUI
                    // doesn't observe its @Published property changes directly.)
                    selectedFileURL = url
                    appDelegate?.recentWorkspaces.add(.localFolder(folderURL))
                    appDelegate?.updateFolderWindowFile(folder: folderURL, to: url)
                    if let window = NSApp.keyWindow {
                        window.title = url.displayPath
                    }
                } catch {
                    print("[FolderWindowContent] Failed to load file: \(error)")
                }
            }
        } else {
            // First file selection — create DocumentState (synchronous)
            let content = (try? String(contentsOf: url, encoding: .utf8)) ?? "Error loading file"
            documentState = DocumentState(content: content, fileURL: url)
            selectedFileURL = url
            appDelegate?.recentWorkspaces.add(.localFolder(folderURL))
            appDelegate?.updateFolderWindowFile(folder: folderURL, to: url)
            if let window = NSApp.keyWindow {
                window.title = url.displayPath
            }
        }
    }

    private func executePrint() {
        guard selectedFileURL != nil else { return }
        guard let webView = findController.webView,
              let window = NSApp.mainWindow ?? NSApp.keyWindow else { return }

        let printConfig = PrintConfiguration(
            includeGutter: showGutter,
            includeLineNumbers: showLineNumbers,
            fontSize: prefs.printFontSize,
            margins: prefs.printMargins
        )

        MarkdownWebView.preparePrint(webView: webView, config: printConfig) { [weak webView] in
            guard let webView = webView else { return }

            webView.setValue(true, forKey: "drawsBackground")

            let printInfo = NSPrintInfo.shared
            printInfo.paperSize = NSSize(width: 595.28, height: 841.89)
            printInfo.topMargin = printConfig.margins.top
            printInfo.bottomMargin = printConfig.margins.bottom
            printInfo.leftMargin = printConfig.margins.left
            printInfo.rightMargin = printConfig.margins.right

            let printOperation = webView.printOperation(with: printInfo)
            if let state = self.documentState {
                printOperation.jobTitle = state.fileURL.deletingPathExtension().lastPathComponent
            }
            printOperation.showsPrintPanel = true
            printOperation.showsProgressPanel = true

            let handler = FolderPrintCompletionHandler(webView: webView, screenTheme: self.effectiveTheme)
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
            printMargins: prefs.printMargins,
            printFontSize: prefs.printFontSize
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
    @Binding var showHiddenFiles: Bool
    @Binding var textWidth: String
    @Binding var contentWidth: String
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
            .onReceive(NotificationCenter.default.publisher(for: .toggleHiddenFiles)) { _ in
                if checkIsKeyWindow() { showHiddenFiles.toggle() }
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
            .onReceive(NotificationCenter.default.publisher(for: .setTextWidth)) { notification in
                if checkIsKeyWindow(), let value = notification.userInfo?["value"] as? String {
                    textWidth = value
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .setContentWidth)) { notification in
                if checkIsKeyWindow(), let value = notification.userInfo?["value"] as? String {
                    contentWidth = value
                }
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
    private let screenTheme: String

    init(webView: WKWebView, screenTheme: String) {
        self.webView = webView
        self.screenTheme = screenTheme
        super.init()
    }

    @objc func printOperationDidRun(
        _ operation: NSPrintOperation,
        success: Bool,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        webView.setValue(false, forKey: "drawsBackground")
        MarkdownWebView.restoreFromPrint(webView: webView, screenTheme: screenTheme)
    }
}

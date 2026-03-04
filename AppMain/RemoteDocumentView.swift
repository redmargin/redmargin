import SwiftUI
import WebKit
import UserNotifications
import RedmarginLib
import RedmarginCore

struct RemoteDocumentWindowContent: View {
    @State private var state: RemoteDocumentState
    @StateObject private var findController = FindController()
    @StateObject private var fileTreeProvider: RemoteFileTreeProvider
    @ObservedObject private var prefs = PreferencesManager.shared
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var showSidebar: Bool
    @State private var sidebarWidth: CGFloat
    @State private var showGutter: Bool
    @State private var showLineNumbers: Bool = false
    @State private var showGitIndicators: Bool
    @State private var showFindBar: Bool = false
    @State private var findBarFocusTrigger: UUID = UUID()
    @State private var isExporting: Bool = false
    weak var appDelegate: AppDelegate?

    let location: RemoteLocation

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

    /// Whether this window was opened as a folder (no initial file)
    @State private var isFolderMode: Bool

    init(
        content: String,
        location: RemoteLocation,
        fileProvider: RemoteFileProvider,
        showSidebar: Bool? = nil,
        sidebarWidth: CGFloat? = nil,
        appDelegate: AppDelegate? = nil
    ) {
        let prefs = PreferencesManager.shared
        self.location = location
        self.appDelegate = appDelegate
        _isFolderMode = State(initialValue: false)
        _showSidebar = State(initialValue: showSidebar ?? false)
        _sidebarWidth = State(initialValue: sidebarWidth ?? 200)
        _showGutter = State(initialValue: prefs.showGutter)
        _showGitIndicators = State(initialValue: prefs.showGitIndicators)
        _state = State(initialValue: RemoteDocumentState(
            content: content,
            location: location,
            fileProvider: fileProvider
        ))
        _fileTreeProvider = StateObject(wrappedValue: RemoteFileTreeProvider(
            currentFilePath: location.path,
            fileProvider: fileProvider,
            stateChanges: fileProvider.stateChanges
        ))
    }

    /// Folder-mode init: opens a remote directory with sidebar, no file loaded initially.
    init(
        folderPath: String,
        host: String,
        fileProvider: RemoteFileProvider,
        showSidebar: Bool? = nil,
        sidebarWidth: CGFloat? = nil,
        appDelegate: AppDelegate? = nil
    ) {
        let prefs = PreferencesManager.shared
        let location = RemoteLocation(host: host, path: folderPath)
        self.location = location
        self.appDelegate = appDelegate
        _isFolderMode = State(initialValue: true)
        _showSidebar = State(initialValue: showSidebar ?? true)
        _sidebarWidth = State(initialValue: sidebarWidth ?? 200)
        _showGutter = State(initialValue: prefs.showGutter)
        _showGitIndicators = State(initialValue: prefs.showGitIndicators)
        _state = State(initialValue: RemoteDocumentState(
            content: "",
            location: location,
            fileProvider: fileProvider
        ))
        _fileTreeProvider = StateObject(wrappedValue: RemoteFileTreeProvider(
            currentFilePath: folderPath,
            fileProvider: fileProvider,
            stateChanges: fileProvider.stateChanges,
            isDirectory: true
        ))
    }

    private var remoteBasePath: String {
        (state.location.path as NSString).deletingLastPathComponent
    }

    var body: some View {
        splitViewContent
            .frame(minWidth: 500, idealWidth: 750, minHeight: 400, idealHeight: 1000)
            .modifier(RemoteNotificationModifiers(
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
            .modifier(RemotePersistenceModifiers(
                location: state.location,
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
            .alert("Remote File Changed", isPresented: $state.showConflictDialog) {
                Button("Overwrite Remote") {
                    state.resolveConflictKeepLocalToggle()
                }
                Button("Reload from Server", role: .destructive) {
                    state.resolveConflictReloadFromServer()
                }
            } message: {
                Text("""
                    The file on the server changed while you were disconnected, \
                    and you have a pending checkbox toggle. Choose how to resolve this conflict.
                    """)
            }
            .onAppear {
                loadPersistedSettings()
            }
    }

    @ViewBuilder
    private var splitViewContent: some View {
        SidebarSplitView(
            sidebar: { sidebarContent },
            content: { mainContent },
            isSidebarVisible: $showSidebar,
            sidebarWidth: $sidebarWidth
        )
    }

    @ViewBuilder
    private var sidebarContent: some View {
        SidebarView(
            rootNodes: fileTreeProvider.rootNodes,
            rootDirectory: fileTreeProvider.rootDirectory,
            currentFileURL: URL(fileURLWithPath: state.location.path),
            isLoading: fileTreeProvider.isLoading,
            onFileSelected: { url in
                handleFileSelection(url)
            },
            onRefresh: {
                state.refresh()
                fileTreeProvider.refresh()
            }
        )
    }

    private func loadPersistedSettings() {
        let settings = DocumentSettingsStorage.shared
        let loc = state.location
        if let loaded = settings.loadGutterVisible(for: loc) {
            showGutter = loaded
        }
        showLineNumbers = settings.loadLineNumbersVisible(for: loc)
        if let loaded = settings.loadGitIndicatorsVisible(for: loc) {
            showGitIndicators = loaded
        }
        if let loaded = settings.loadSidebarVisible(for: loc) {
            showSidebar = loaded
        }
        if let loaded = settings.loadSidebarWidth(for: loc) {
            sidebarWidth = loaded
        }

        // Set up expanded folders persistence
        setupExpandedFoldersPersistence()
    }

    private func setupExpandedFoldersPersistence() {
        let settings = DocumentSettingsStorage.shared
        let host = state.location.host

        // Set up callback for saving expanded folders
        fileTreeProvider.onExpandedFoldersChange = { rootPath, expandedPaths in
            settings.saveExpandedFolders(expandedPaths, forRemoteHost: host, rootPath: rootPath)
        }

        // Load and apply saved expanded folders once rootDirectory is available
        Task { @MainActor in
            // Wait for FileTreeProvider to finish loading
            while fileTreeProvider.isLoading {
                try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
            }

            if let rootPath = fileTreeProvider.rootDirectory {
                let expandedFolders = settings.loadExpandedFolders(forRemoteHost: host, rootPath: rootPath)
                if !expandedFolders.isEmpty {
                    fileTreeProvider.applyExpandedFolders(expandedFolders)
                }
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if isFolderMode && state.content.isEmpty {
            remoteFolderWelcomeView
        } else {
            documentContent
        }
    }

    private var remoteFolderWelcomeView: some View {
        ContentUnavailableView(
            "No Selection",
            systemImage: "doc.text",
            description: Text("Select a file from the sidebar")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var documentContent: some View {
        ZStack(alignment: .top) {
            MarkdownWebView(
                markdown: state.content,
                fileURL: URL(fileURLWithPath: state.location.path),
                onCheckboxToggle: state.handleCheckboxToggle,
                onScrollPositionChange: { position in
                    DocumentSettingsStorage.shared.saveScrollPosition(position, for: state.location)
                },
                initialScrollPosition: DocumentSettingsStorage.shared.loadScrollPosition(for: state.location),
                showLineNumbers: showLineNumbers,
                gitChanges: state.gitChanges,
                findController: findController,
                theme: effectiveTheme,
                inlineCodeColor: prefs.inlineCodeColor.rawValue,
                allowRemoteImages: prefs.allowRemoteImages,
                showGutter: showGutter,
                showGitIndicators: showGitIndicators,
                cacheBust: state.refreshToken,
                remoteBasePath: remoteBasePath,
                remoteAssetFetcher: { [weak state] path in
                    guard let state = state else { return nil }
                    let result = try await state.readAsset(path: path)
                    return result
                }
            )

            // Connection status overlay
            if state.connectionState != .connected {
                connectionStatusOverlay
            }

            if state.isRefreshing || isExporting {
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
    }

    @ViewBuilder
    private var connectionStatusOverlay: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    switch state.connectionState {
                    case .reconnecting:
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Reconnecting...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    case .disconnected:
                        Image(systemName: "wifi.slash")
                            .foregroundColor(.red)
                        Text("Disconnected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    case .connecting:
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Connecting...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    case .connected:
                        EmptyView()
                    }
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                Spacer()
            }
            Spacer()
        }
        .background(Color.black.opacity(0.3))
    }

    private var isKeyWindow: Bool {
        guard let window = NSApp.keyWindow else { return false }
        typealias HostingVC = NSHostingController<RemoteDocumentWindowContent>
        guard let hostingController = window.contentViewController as? HostingVC else {
            return false
        }
        return hostingController.rootView.location == location
    }

    private func dismissFindBar() {
        showFindBar = false
        findController.clearFind()
    }

    private func handleFileSelection(_ url: URL) {
        let selectedPath = url.path
        let oldLocation = state.location
        guard selectedPath != oldLocation.path else { return }

        Task {
            do {
                try await state.loadFile(at: selectedPath)
                isFolderMode = false  // Exit welcome view once a file is loaded
                let newLocation = RemoteLocation(host: oldLocation.host, path: selectedPath)
                appDelegate?.updateRemoteWindowTracking(from: oldLocation, to: newLocation)

                // Save current view settings for the new location
                let settings = DocumentSettingsStorage.shared
                settings.saveSidebarVisible(showSidebar, for: newLocation)
                settings.saveSidebarWidth(sidebarWidth, for: newLocation)
                settings.saveGutterVisible(showGutter, for: newLocation)
                settings.saveLineNumbersVisible(showLineNumbers, for: newLocation)
                settings.saveGitIndicatorsVisible(showGitIndicators, for: newLocation)
            } catch {
                print("[RemoteDocumentView] Failed to load file: \(error)")
            }
        }
    }

    private func executePrint() {
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
            let filename = (self.state.location.path as NSString).lastPathComponent
            printOperation.jobTitle = (filename as NSString).deletingPathExtension
            printOperation.showsPrintPanel = true
            printOperation.showsProgressPanel = true

            let handler = RemotePrintCompletionHandler(webView: webView, printClasses: classes)
            objc_setAssociatedObject(printOperation, "handler", handler, .OBJC_ASSOCIATION_RETAIN)

            printOperation.runModal(
                for: window,
                delegate: handler,
                didRun: #selector(RemotePrintCompletionHandler.printOperationDidRun(_:success:contextInfo:)),
                contextInfo: nil
            )
        }
    }

    private func executeExport() {
        guard let webView = findController.webView else { return }
        guard !isExporting else { return }

        isExporting = true
        let pathComponent = (state.location.path as NSString).lastPathComponent
        let filename = (pathComponent as NSString).deletingPathExtension

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

private class RemotePrintCompletionHandler: NSObject {
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

private struct RemoteNotificationModifiers: ViewModifier {
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

private struct RemotePersistenceModifiers: ViewModifier {
    let location: RemoteLocation
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
                settings.saveGutterVisible(newValue, for: location)
            }
            .onChange(of: showLineNumbers) { _, newValue in
                settings.saveLineNumbersVisible(newValue, for: location)
            }
            .onChange(of: showGitIndicators) { _, newValue in
                settings.saveGitIndicatorsVisible(newValue, for: location)
            }
            .onChange(of: showSidebar) { _, newValue in
                settings.saveSidebarVisible(newValue, for: location)
            }
            .onChange(of: sidebarWidth) { _, newValue in
                settings.saveSidebarWidth(newValue, for: location)
            }
            .onChange(of: findSearchText) { _, newValue in
                onFind(newValue)
            }
    }
}

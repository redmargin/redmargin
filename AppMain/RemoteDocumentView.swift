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
    @State private var textWidth: String
    @State private var contentWidth: String
    @State private var showHiddenFiles: Bool = false
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
        let settings = DocumentSettingsStorage.shared
        _textWidth = State(initialValue: settings.loadTextWidth(for: location) ?? prefs.textWidth.rawValue)
        _contentWidth = State(initialValue: settings.loadContentWidth(for: location) ?? prefs.contentWidth.rawValue)
        _state = State(initialValue: RemoteDocumentState(
            content: content,
            location: location,
            fileProvider: fileProvider
        ))
        let hostForLoader = location.host
        _fileTreeProvider = StateObject(wrappedValue: RemoteFileTreeProvider(
            currentFilePath: location.path,
            fileProvider: fileProvider,
            reconnectHost: location.host,
            expandedFoldersLoader: { rootPath in
                DocumentSettingsStorage.shared.loadExpandedFolders(forRemoteHost: hostForLoader, rootPath: rootPath)
            }
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
        _textWidth = State(initialValue: prefs.textWidth.rawValue)
        _contentWidth = State(initialValue: prefs.contentWidth.rawValue)
        _state = State(initialValue: RemoteDocumentState(
            content: "",
            location: location,
            fileProvider: fileProvider
        ))
        _fileTreeProvider = StateObject(wrappedValue: RemoteFileTreeProvider(
            currentFilePath: folderPath,
            fileProvider: fileProvider,
            reconnectHost: host,
            isDirectory: true,
            expandedFoldersLoader: { rootPath in
                DocumentSettingsStorage.shared.loadExpandedFolders(forRemoteHost: host, rootPath: rootPath)
            }
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
                showHiddenFiles: $showHiddenFiles,
                textWidth: $textWidth,
                contentWidth: $contentWidth,
                showFindBar: $showFindBar,
                findBarFocusTrigger: $findBarFocusTrigger,
                sidebarWidth: sidebarWidth,
                onRefresh: {
                    let route = remoteRefreshRoute(
                        isFolderMode: isFolderMode,
                        sidebarVisible: showSidebar,
                        source: .commandRefresh
                    )
                    if route == .documentOnly || route == .documentAndSidebar {
                        state.refresh()
                    }
                    if route == .sidebarOnly || route == .documentAndSidebar {
                        fileTreeProvider.refresh()
                    }
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
                showHiddenFiles: showHiddenFiles,
                textWidth: textWidth,
                contentWidth: contentWidth,
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
            .onChange(of: showHiddenFiles) { _, newValue in
                fileTreeProvider.showHiddenFiles = newValue
            }
            .onChange(of: prefs.showSidebarGitStatus) { _, newValue in
                fileTreeProvider.showGitStatus = newValue
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
                fileTreeProvider.showGitStatus = prefs.showSidebarGitStatus
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
                let route = remoteRefreshRoute(
                    isFolderMode: isFolderMode,
                    sidebarVisible: true,
                    source: .sidebarButton
                )
                if route == .documentOnly || route == .documentAndSidebar {
                    state.refresh()
                }
                if route == .sidebarOnly || route == .documentAndSidebar {
                    fileTreeProvider.refresh()
                }
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
        if let loaded = settings.loadHiddenFilesVisible(for: loc) {
            showHiddenFiles = loaded
        }
        fileTreeProvider.showHiddenFiles = showHiddenFiles

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
                textWidth: textWidth,
                contentWidth: contentWidth,
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
            let filename = (self.state.location.path as NSString).lastPathComponent
            printOperation.jobTitle = (filename as NSString).deletingPathExtension
            printOperation.showsPrintPanel = true
            printOperation.showsProgressPanel = true

            let handler = RemotePrintCompletionHandler(webView: webView, screenTheme: self.effectiveTheme)
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
            printMargins: prefs.printMargins,
            printFontSize: prefs.printFontSize
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

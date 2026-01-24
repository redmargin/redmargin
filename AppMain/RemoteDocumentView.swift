import SwiftUI
import WebKit
import UserNotifications
import RedmarginLib
import RedmarginCore

struct RemoteDocumentWindowContent: View {
    @StateObject private var state: RemoteDocumentState
    @StateObject private var findController = FindController()
    @ObservedObject private var prefs = PreferencesManager.shared
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var showLineNumbers: Bool = false
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

    private var shouldShowGutter: Bool {
        if state.gitChanges != nil {
            return true
        }
        return prefs.gutterVisibilityForNonRepo == .showEmpty
    }

    init(
        content: String,
        location: RemoteLocation,
        fileProvider: RemoteFileProvider,
        appDelegate: AppDelegate? = nil
    ) {
        self.location = location
        self.appDelegate = appDelegate
        _state = StateObject(wrappedValue: RemoteDocumentState(
            content: content,
            location: location,
            fileProvider: fileProvider
        ))
    }

    private var remoteBasePath: String {
        (location.path as NSString).deletingLastPathComponent
    }

    var body: some View {
        ZStack(alignment: .top) {
            MarkdownWebView(
                markdown: state.content,
                fileURL: URL(fileURLWithPath: location.path),
                onCheckboxToggle: state.handleCheckboxToggle,
                onScrollPositionChange: { [weak appDelegate] position in
                    appDelegate?.saveScrollPosition(position, for: location)
                },
                initialScrollPosition: appDelegate?.loadScrollPosition(for: location) ?? 0,
                showLineNumbers: showLineNumbers,
                gitChanges: state.gitChanges,
                findController: findController,
                theme: effectiveTheme,
                inlineCodeColor: prefs.inlineCodeColor.rawValue,
                allowRemoteImages: prefs.allowRemoteImages,
                showGutter: shouldShowGutter,
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
                findBarFocusTrigger = UUID()
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
        .onReceive(NotificationCenter.default.publisher(for: .exportToPDF)) { _ in
            if isKeyWindow {
                executeExport()
            }
        }
        .onChange(of: findController.searchText) { _, newValue in
            findController.find(newValue)
        }
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

    private func executePrint() {
        guard let webView = findController.webView,
              let window = NSApp.mainWindow ?? NSApp.keyWindow else { return }

        var classes: [String] = ["print-light-theme"]
        if !shouldShowGutter {
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
            let filename = (self.location.path as NSString).lastPathComponent
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
        let pathComponent = (location.path as NSString).lastPathComponent
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

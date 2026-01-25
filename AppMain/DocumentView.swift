import SwiftUI
import WebKit
import UserNotifications
import RedmarginLib
import RedmarginCore

struct DocumentWindowContent: View {
    @StateObject private var state: DocumentState
    @StateObject private var findController = FindController()
    @ObservedObject private var prefs = PreferencesManager.shared
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var showGutter: Bool
    @State private var showLineNumbers: Bool
    @State private var showGitIndicators: Bool
    @State private var showFindBar: Bool = false
    @State private var findBarFocusTrigger: UUID = UUID()
    @State private var isExporting: Bool = false
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

    init(
        content: String,
        fileURL: URL,
        initialScrollPosition: Double = 0,
        showGutter: Bool? = nil,
        showLineNumbers: Bool? = nil,
        showGitIndicators: Bool? = nil,
        appDelegate: AppDelegate? = nil,
        onScrollPositionChange: @escaping (Double) -> Void = { _ in }
    ) {
        let prefs = PreferencesManager.shared
        _state = StateObject(wrappedValue: DocumentState(content: content, fileURL: fileURL))
        _showGutter = State(initialValue: showGutter ?? prefs.showGutter)
        _showLineNumbers = State(initialValue: showLineNumbers ?? prefs.showLineNumbers)
        _showGitIndicators = State(initialValue: showGitIndicators ?? prefs.showGitIndicators)
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
                onFirstRenderComplete: {
                    NotificationCenter.default.post(
                        name: .windowContentReady,
                        object: nil,
                        userInfo: ["fileURL": fileURL]
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
                cacheBust: state.refreshToken
            )

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
        .onReceive(NotificationCenter.default.publisher(for: .toggleGutter)) { _ in
            if isKeyWindow {
                showGutter.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleLineNumbers)) { _ in
            if isKeyWindow {
                showLineNumbers.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleGitIndicators)) { _ in
            if isKeyWindow {
                showGitIndicators.toggle()
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
        .onReceive(NotificationCenter.default.publisher(for: .exportToPDF)) { _ in
            if isKeyWindow {
                executeExport()
            }
        }
        .onChange(of: showGutter) { _, newValue in
            appDelegate?.saveGutterVisible(newValue, for: fileURL)
        }
        .onChange(of: showLineNumbers) { _, newValue in
            appDelegate?.saveLineNumbersVisible(newValue, for: fileURL)
        }
        .onChange(of: showGitIndicators) { _, newValue in
            appDelegate?.saveGitIndicatorsVisible(newValue, for: fileURL)
        }
        .onChange(of: findController.searchText) { _, newValue in
            findController.find(newValue)
        }
        .onKeyPress(.escape) {
            guard showFindBar else { return .ignored }
            dismissFindBar()
            return .handled
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
            printOperation.jobTitle = self.fileURL.deletingPathExtension().lastPathComponent
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
        let filename = fileURL.deletingPathExtension().lastPathComponent

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

import SwiftUI
import WebKit
import RedmarginLib
import RedmarginCore

// MARK: - Print Completion Handler

class RemotePrintCompletionHandler: NSObject {
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

struct RemoteNotificationModifiers: ViewModifier {
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
            .onReceive(NotificationCenter.default.publisher(for: .toggleHiddenFiles)) { _ in
                if checkIsKeyWindow() { showHiddenFiles.toggle() }
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

struct RemotePersistenceModifiers: ViewModifier {
    let location: RemoteLocation
    let showGutter: Bool
    let showLineNumbers: Bool
    let showGitIndicators: Bool
    let showHiddenFiles: Bool
    let textWidth: String
    let contentWidth: String
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
            .onChange(of: showHiddenFiles) { _, newValue in
                settings.saveHiddenFilesVisible(newValue, for: location)
            }
            .onChange(of: textWidth) { _, newValue in
                settings.saveTextWidth(newValue, for: location)
            }
            .onChange(of: contentWidth) { _, newValue in
                settings.saveContentWidth(newValue, for: location)
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

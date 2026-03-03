import AppKit
import SwiftUI
import WebKit
import RedmarginCore

public struct MarkdownWebView: NSViewRepresentable {
    public let markdown: String
    public let fileURL: URL?
    public var onCheckboxToggle: ((Int, Bool) -> Void)?
    public var onScrollPositionChange: ((Double) -> Void)?
    public var onFirstRenderComplete: (() -> Void)?
    public var initialScrollPosition: Double
    public var showLineNumbers: Bool
    public var gitChanges: GitChangeResult?
    public var findController: FindController?
    public var theme: String
    public var inlineCodeColor: String
    public var allowRemoteImages: Bool
    public var showGutter: Bool
    public var showGitIndicators: Bool
    public var textWidth: String
    public var contentWidth: String
    public var cacheBust: Int  // Token to bust image cache on refresh
    public var remoteBasePath: String?  // Remote path for custom scheme
    public var remoteAssetFetcher: ((String) async throws -> (Data, String)?)?

    public init(
        markdown: String,
        fileURL: URL?,
        onCheckboxToggle: ((Int, Bool) -> Void)? = nil,
        onScrollPositionChange: ((Double) -> Void)? = nil,
        onFirstRenderComplete: (() -> Void)? = nil,
        initialScrollPosition: Double = 0,
        showLineNumbers: Bool = true,
        gitChanges: GitChangeResult? = nil,
        findController: FindController? = nil,
        theme: String = "light",
        inlineCodeColor: String = "warm",
        allowRemoteImages: Bool = false,
        showGutter: Bool = true,
        showGitIndicators: Bool = true,
        textWidth: String = "medium",
        contentWidth: String = "unrestricted",
        cacheBust: Int = 0,
        remoteBasePath: String? = nil,
        remoteAssetFetcher: ((String) async throws -> (Data, String)?)? = nil
    ) {
        self.markdown = markdown
        self.fileURL = fileURL
        self.onCheckboxToggle = onCheckboxToggle
        self.onScrollPositionChange = onScrollPositionChange
        self.onFirstRenderComplete = onFirstRenderComplete
        self.initialScrollPosition = initialScrollPosition
        self.showLineNumbers = showLineNumbers
        self.gitChanges = gitChanges
        self.findController = findController
        self.theme = theme
        self.inlineCodeColor = inlineCodeColor
        self.allowRemoteImages = allowRemoteImages
        self.showGutter = showGutter
        self.showGitIndicators = showGitIndicators
        self.textWidth = textWidth
        self.contentWidth = contentWidth
        self.cacheBust = cacheBust
        self.remoteBasePath = remoteBasePath
        self.remoteAssetFetcher = remoteAssetFetcher
    }

    public func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.setValue(false, forKey: "allowFileAccessFromFileURLs")
        configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()

        // Always register scheme handler that delegates to coordinator
        // This allows the fetcher to be set/updated later via coordinator
        let coordinator = context.coordinator
        let schemeHandler = RemoteAssetSchemeHandler { path in
            // Delegate to coordinator's fetcher
            guard let fetcher = coordinator.remoteAssetFetcher else {
                return nil
            }
            return try await fetcher(path)
        }
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: RemoteAssetSchemeHandler.scheme)

        // Set initial fetcher if available
        coordinator.remoteAssetFetcher = remoteAssetFetcher

        let contentController = configuration.userContentController
        contentController.add(context.coordinator, name: "checkboxToggle")
        contentController.add(context.coordinator, name: "scrollPosition")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsLinkPreview = false

        context.coordinator.onCheckboxToggle = onCheckboxToggle
        context.coordinator.onScrollPositionChange = onScrollPositionChange
        context.coordinator.onFirstRenderComplete = onFirstRenderComplete
        context.coordinator.initialScrollPosition = initialScrollPosition
        context.coordinator.lastAllowRemoteImages = allowRemoteImages

        // Wire up find controller
        findController?.webView = webView

        // Load content rules for remote resource blocking
        loadContentRules(webView: webView, allowRemoteImages: allowRemoteImages)

        loadRenderer(webView: webView)

        return webView
    }

    private func loadContentRules(webView: WKWebView, allowRemoteImages: Bool) {
        ContentRuleList.compileForPreference(allowRemoteImages: allowRemoteImages) { ruleList in
            if let ruleList = ruleList {
                webView.configuration.userContentController.add(ruleList)
            }
        }
    }

    public func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onCheckboxToggle = onCheckboxToggle
        context.coordinator.onScrollPositionChange = onScrollPositionChange
        context.coordinator.remoteAssetFetcher = remoteAssetFetcher

        // Detect file change (e.g. switching files in folder window)
        if context.coordinator.lastFileURL != fileURL {
            context.coordinator.lastFileURL = fileURL
            context.coordinator.hasRestoredInitialScroll = false
        }

        // Update content rules if allowRemoteImages preference changed
        if context.coordinator.lastAllowRemoteImages != allowRemoteImages {
            context.coordinator.lastAllowRemoteImages = allowRemoteImages
            updateContentRules(webView: webView, allowRemoteImages: allowRemoteImages)
        }

        // Use remote base path with custom scheme, or local file path
        let basePath: String
        if let remotePath = remoteBasePath {
            basePath = "\(RemoteAssetSchemeHandler.scheme)://\(remotePath)"
        } else {
            basePath = fileURL?.deletingLastPathComponent().path ?? ""
        }
        let params = RenderParams(
            markdown: markdown,
            theme: theme,
            basePath: basePath,
            scrollPosition: initialScrollPosition,
            gitChanges: gitChanges,
            inlineCodeColor: inlineCodeColor,
            showGutter: showGutter,
            showGitIndicators: showGitIndicators,
            textWidth: textWidth,
            contentWidth: contentWidth,
            cacheBust: cacheBust
        )

        if context.coordinator.isLoaded {
            // Only restore scroll on first render after load
            let shouldRestoreScroll = !context.coordinator.hasRestoredInitialScroll
            Self.render(webView: webView, params: params, restoreScroll: shouldRestoreScroll)
            context.coordinator.hasRestoredInitialScroll = true

            // Update line numbers visibility if changed
            if context.coordinator.lastLineNumbersVisible != showLineNumbers {
                context.coordinator.lastLineNumbersVisible = showLineNumbers
                Self.setLineNumbersVisible(webView: webView, visible: showLineNumbers)
            }
        } else {
            context.coordinator.pendingRender = params
            context.coordinator.pendingLineNumbersVisible = showLineNumbers
        }
    }

    private func updateContentRules(webView: WKWebView, allowRemoteImages: Bool) {
        let contentController = webView.configuration.userContentController
        contentController.removeAllContentRuleLists()
        loadContentRules(webView: webView, allowRemoteImages: allowRemoteImages)
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func loadRenderer(webView: WKWebView) {
        guard let resourceURL = Bundle.main.resourceURL else {
            print("Failed to get bundle resource URL")
            return
        }

        let rendererURL = resourceURL
            .appendingPathComponent("WebRenderer")
            .appendingPathComponent("src")
            .appendingPathComponent("renderer.html")

        // Allow read access to root so WebView can load both renderer assets and document images
        let accessURL = URL(fileURLWithPath: "/")
        webView.loadFileURL(rendererURL, allowingReadAccessTo: accessURL)
    }

    static func render(
        webView: WKWebView,
        params: RenderParams,
        restoreScroll: Bool = false,
        completion: (() -> Void)? = nil
    ) {
        var payload: [String: Any] = [
            "markdown": params.markdown,
            "options": [
                "theme": params.theme,
                "basePath": params.basePath,
                "inlineCodeColor": params.inlineCodeColor,
                "showGutter": params.showGutter,
                "showGitIndicators": params.showGitIndicators,
                "textWidth": params.textWidth,
                "contentWidth": params.contentWidth,
                "cacheBust": params.cacheBust
            ]
        ]

        // Add git changes if available
        if let changes = params.gitChanges,
           let changesData = try? JSONEncoder().encode(changes),
           let changesDict = try? JSONSerialization.jsonObject(with: changesData) as? [String: Any] {
            payload["changes"] = changesDict
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            completion?()
            return
        }

        let escapedJSON = jsonString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")

        let script = "window.App.render(JSON.parse('\(escapedJSON)'))"
        webView.evaluateJavaScript(script) { _, error in
            if let error = error {
                print("Render error: \(error)")
            }
            completion?()
        }

        // Only restore scroll on initial load, not on content updates
        // (JS handles scroll preservation on content changes)
        if restoreScroll {
            let scrollScript = "window.ScrollPosition.restore(\(params.scrollPosition))"
            webView.evaluateJavaScript(scrollScript, completionHandler: nil)
        }
    }

    static func setLineNumbersVisible(webView: WKWebView, visible: Bool) {
        let script = "window.LineNumbers.setVisible(\(visible))"
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    static func setTheme(webView: WKWebView, theme: String) {
        let script = "window.App.setTheme('\(theme)')"
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    static func setInlineCodeColor(webView: WKWebView, colorName: String) {
        let script = "window.App.setInlineCodeColor('\(colorName)')"
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    public static func preparePrint(webView: WKWebView, config: PrintConfiguration, completion: @escaping () -> Void) {
        var classes: [String] = ["print-light-theme"]
        if !config.includeGutter {
            classes.append("print-hide-gutter")
        }
        if !config.includeLineNumbers {
            classes.append("print-hide-line-numbers")
        }
        let classString = classes.joined(separator: " ")
        let script = "document.body.classList.add(...'\(classString)'.split(' '))"
        webView.evaluateJavaScript(script) { _, _ in
            completion()
        }
    }

    public static func restoreFromPrint(webView: WKWebView) {
        let script = """
            document.body.classList.remove('print-light-theme', 'print-hide-gutter', 'print-hide-line-numbers')
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    struct RenderParams {
        let markdown: String
        let theme: String
        let basePath: String
        var scrollPosition: Double = 0
        var gitChanges: GitChangeResult?
        var inlineCodeColor: String = "warm"
        var showGutter: Bool = true
        var showGitIndicators: Bool = true
        var textWidth: String = "medium"
        var contentWidth: String = "unrestricted"
        var cacheBust: Int = 0
    }
}

// MARK: - Coordinator

extension MarkdownWebView {
    public class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var isLoaded = false
        var hasRestoredInitialScroll = false
        var hasFiredFirstRenderComplete = false
        var pendingRender: RenderParams?
        var pendingLineNumbersVisible: Bool = true
        var lastLineNumbersVisible: Bool = true
        var lastAllowRemoteImages: Bool = false
        var onCheckboxToggle: ((Int, Bool) -> Void)?
        var onScrollPositionChange: ((Double) -> Void)?
        var onFirstRenderComplete: (() -> Void)?
        var initialScrollPosition: Double = 0
        var lastFileURL: URL?
        // Remote asset fetcher - can be updated after WKWebView is created
        var remoteAssetFetcher: ((String) async throws -> (Data, String)?)?

        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true

            if let pending = pendingRender {
                // Initial render - restore scroll position
                MarkdownWebView.render(webView: webView, params: pending, restoreScroll: true) { [weak self] in
                    // Fire callback after first render completes
                    guard let self = self, !self.hasFiredFirstRenderComplete else { return }
                    self.hasFiredFirstRenderComplete = true
                    self.onFirstRenderComplete?()
                }
                hasRestoredInitialScroll = true
                pendingRender = nil

                // Apply pending line numbers visibility
                lastLineNumbersVisible = pendingLineNumbersVisible
                MarkdownWebView.setLineNumbersVisible(webView: webView, visible: pendingLineNumbersVisible)
            }
        }

        public func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            let scheme = url.scheme?.lowercased()

            // Allow initial page load and internal navigation
            if navigationAction.navigationType == .other ||
               navigationAction.navigationType == .reload ||
               navigationAction.navigationType == .backForward {
                decisionHandler(.allow)
                return
            }

            // Handle link clicks
            if navigationAction.navigationType == .linkActivated {
                switch scheme {
                case "http", "https":
                    // Open external links in system browser
                    NSWorkspace.shared.open(url)
                    decisionHandler(.cancel)
                    return

                case "mailto":
                    // Let system handle mailto links
                    NSWorkspace.shared.open(url)
                    decisionHandler(.cancel)
                    return

                case "file":
                    // Handle same-page anchor navigation (fragment links like #section)
                    if let fragment = url.fragment,
                       let currentURL = webView.url,
                       url.path == currentURL.path {
                        // Use JavaScript to scroll to the anchor instead of allowing navigation
                        // (allowing navigation would reload the page)
                        // Escape fragment for safe JavaScript string embedding
                        let escapedFragment = fragment
                            .replacingOccurrences(of: "\\", with: "\\\\")
                            .replacingOccurrences(of: "'", with: "\\'")
                        let script = """
                            (function() {
                                var element = document.getElementById('\(escapedFragment)');
                                if (element) {
                                    element.scrollIntoView({ behavior: 'smooth', block: 'start' });
                                }
                            })();
                        """
                        webView.evaluateJavaScript(script, completionHandler: nil)
                        decisionHandler(.cancel)
                        return
                    }
                    // Block navigation to other local files (security)
                    decisionHandler(.cancel)
                    return

                default:
                    // Block unknown schemes
                    print("[Navigation] Blocked unknown scheme: \(scheme ?? "nil")")
                    decisionHandler(.cancel)
                    return
                }
            }

            // Allow other navigation types (resource loads, etc.)
            decisionHandler(.allow)
        }

        public func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if message.name == "checkboxToggle",
               let body = message.body as? [String: Any],
               let line = body["line"] as? Int,
               let checked = body["checked"] as? Bool {
                onCheckboxToggle?(line, checked)
            } else if message.name == "scrollPosition",
                      let body = message.body as? [String: Any],
                      let scrollY = body["scrollY"] as? Double {
                onScrollPositionChange?(scrollY)
            }
        }
    }
}

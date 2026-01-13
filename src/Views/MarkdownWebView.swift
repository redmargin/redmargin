import SwiftUI
import WebKit

public struct MarkdownWebView: NSViewRepresentable {
    public let markdown: String
    public let fileURL: URL?
    public var onCheckboxToggle: ((Int, Bool) -> Void)?
    public var onScrollPositionChange: ((Double) -> Void)?
    public var initialScrollPosition: Double
    public var showLineNumbers: Bool
    public var gitChanges: GitChangeResult?
    public var findController: FindController?
    public var theme: String
    public var inlineCodeColor: String
    public var allowRemoteImages: Bool
    public var showGutter: Bool

    public init(
        markdown: String,
        fileURL: URL?,
        onCheckboxToggle: ((Int, Bool) -> Void)? = nil,
        onScrollPositionChange: ((Double) -> Void)? = nil,
        initialScrollPosition: Double = 0,
        showLineNumbers: Bool = true,
        gitChanges: GitChangeResult? = nil,
        findController: FindController? = nil,
        theme: String = "light",
        inlineCodeColor: String = "warm",
        allowRemoteImages: Bool = false,
        showGutter: Bool = true
    ) {
        self.markdown = markdown
        self.fileURL = fileURL
        self.onCheckboxToggle = onCheckboxToggle
        self.onScrollPositionChange = onScrollPositionChange
        self.initialScrollPosition = initialScrollPosition
        self.showLineNumbers = showLineNumbers
        self.gitChanges = gitChanges
        self.findController = findController
        self.theme = theme
        self.inlineCodeColor = inlineCodeColor
        self.allowRemoteImages = allowRemoteImages
        self.showGutter = showGutter
    }

    public func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.setValue(false, forKey: "allowFileAccessFromFileURLs")
        configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()

        let contentController = configuration.userContentController
        contentController.add(context.coordinator, name: "checkboxToggle")
        contentController.add(context.coordinator, name: "scrollPosition")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsLinkPreview = false

        context.coordinator.onCheckboxToggle = onCheckboxToggle
        context.coordinator.onScrollPositionChange = onScrollPositionChange
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

        // Update content rules if allowRemoteImages preference changed
        if context.coordinator.lastAllowRemoteImages != allowRemoteImages {
            context.coordinator.lastAllowRemoteImages = allowRemoteImages
            updateContentRules(webView: webView, allowRemoteImages: allowRemoteImages)
        }

        let basePath = fileURL?.deletingLastPathComponent().path ?? ""
        let params = RenderParams(
            markdown: markdown,
            theme: theme,
            basePath: basePath,
            scrollPosition: initialScrollPosition,
            gitChanges: gitChanges,
            inlineCodeColor: inlineCodeColor,
            showGutter: showGutter
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

    static func render(webView: WKWebView, params: RenderParams, restoreScroll: Bool = false) {
        var payload: [String: Any] = [
            "markdown": params.markdown,
            "options": [
                "theme": params.theme,
                "basePath": params.basePath,
                "inlineCodeColor": params.inlineCodeColor,
                "showGutter": params.showGutter
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
        }

        // Only restore scroll on initial load, not on content updates
        // (JS handles scroll preservation on content changes)
        if restoreScroll && params.scrollPosition > 0 {
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
    }

    public class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var isLoaded = false
        var hasRestoredInitialScroll = false
        var pendingRender: RenderParams?
        var pendingLineNumbersVisible: Bool = true
        var lastLineNumbersVisible: Bool = true
        var lastAllowRemoteImages: Bool = false
        var onCheckboxToggle: ((Int, Bool) -> Void)?
        var onScrollPositionChange: ((Double) -> Void)?
        var initialScrollPosition: Double = 0

        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true

            if let pending = pendingRender {
                // Initial render - restore scroll position
                MarkdownWebView.render(webView: webView, params: pending, restoreScroll: true)
                hasRestoredInitialScroll = true
                pendingRender = nil

                // Apply pending line numbers visibility
                lastLineNumbersVisible = pendingLineNumbersVisible
                MarkdownWebView.setLineNumbersVisible(webView: webView, visible: pendingLineNumbersVisible)
            }
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
